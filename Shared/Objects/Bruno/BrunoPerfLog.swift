//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if DEBUG

import Foundation
import OSLog
import UIKit

// MARK: - Bruno on-disk perf telemetry (DEBUG only)

//
// A persistent, append-only JSONL event log that shares the SAME clock and frame index as the
// on-screen debug HUD (BrunoFrameMonitor), so a recorded session correlates against a screen
// recording frame-by-frame. Each line is one JSON object stamped `t` (seconds since the monitor
// started) and `f` (display frame index) — the exact anchors the FRAME panel shows — plus a `kind`
// and a free-form payload.
//
// The writer is the *foundation* other telemetry tasks build on (input capture, view counts,
// content-load timing, INV conflicts): they just call `BrunoPerfLog.event(_:_:)`. This file owns the
// file lifecycle, off-main I/O, the session header, and the two "free" signals (memory sampling +
// a tee of the existing HUD event stream).
//
// Everything is DEBUG-gated and only does work while `isEnabled` (mirrored from
// BrunoDebugFlags.perfLogging) is true; a release build never compiles this and a DEBUG build with
// the toggle off pays nothing past a single bool check per call site.

enum BrunoPerfLog {

    // MARK: Public API

    //
    // STABLE — sibling telemetry tasks depend on these exact signatures.

    /// Whether logging is currently active. Mirrors `BrunoDebugFlags.perfLogging`, which the overlay
    /// modifier drives from the `.brunoPerfLog` default. Every `event(_:_:)` checks this first, so a
    /// disabled logger is a single bool read.
    static var isEnabled: Bool {
        BrunoDebugFlags.perfLogging
    }

    /// The file currently being written, for the HUD indicator and an external pull script. `nil`
    /// until `start()` succeeds; cleared by `stop()`.
    static var sessionFileURL: URL? {
        Writer.shared.sessionFileURL
    }

    /// Open a fresh session file (`<Caches>/BrunoPerf/session-<yyyyMMdd-HHmmss>.jsonl`) and write the
    /// `session` header line. Idempotent: a second call while a session is open is a no-op. Safe to
    /// call off the toggle change — the actual open happens on the writer's serial queue.
    static func start() {
        Writer.shared.start()
    }

    /// Flush any buffered lines and close the current session file. Idempotent.
    static func stop() {
        Writer.shared.stop()
    }

    /// Append one event. Builds `["t": clock, "f": frameIndex, "kind": kind]` merged with `payload`,
    /// serializes it as a single JSON line, and enqueues the write on a serial queue (off main).
    /// No-op when `!isEnabled`. Payload values should be JSON-safe scalars (String / Int / Double /
    /// Bool); anything else is stringified or skipped so a bad value can never crash the app.
    ///
    /// `payload` keys must not collide with the reserved `t` / `f` / `kind` — if they do, the
    /// reserved values win (the timeline anchors are sacred).
    static func event(_ kind: String, _ payload: [String: Any] = [:]) {
        guard isEnabled else { return }
        Writer.shared.event(kind, payload)
    }
}

// MARK: - Writer

private extension BrunoPerfLog {

    /// The actual file machine. All file state (handle, buffer, url) is touched only on `queue`, a
    /// dedicated serial queue, so the render loop never blocks on I/O and there are no data races.
    /// The two cross-thread reads — `isEnabled` (a plain bool elsewhere) and `sessionFileURL` — use a
    /// tiny lock so the HUD can read the filename on the main thread without hopping queues.
    final class Writer {

        static let shared = Writer()

        private static let log = Logger(subsystem: "org.jellyfin.swiftfin.bruno", category: "perflog")

        /// All file mutation runs here, serialized and off the main thread.
        private let queue = DispatchQueue(label: "org.jellyfin.swiftfin.bruno.perflog", qos: .utility)

        // Queue-confined state.
        private var handle: FileHandle?
        private var buffer = Data()
        private var lastFlush: CFTimeInterval = 0

        /// Buffer thresholds — flush on whichever trips first, plus on backgrounding (see notifications).
        private static let flushInterval: CFTimeInterval = 0.5
        private static let flushLineCount = 64

        // Cross-thread readable url (HUD reads it on main). Guarded by `urlLock`.
        private let urlLock = NSLock()
        private var _sessionFileURL: URL?
        var sessionFileURL: URL? {
            urlLock.lock()
            defer { urlLock.unlock() }
            return _sessionFileURL
        }

        private var observersInstalled = false

        private init() {}

        // MARK: Lifecycle

        func start() {
            queue.async { [weak self] in
                self?.openSession()
            }
            installObserversIfNeeded()
        }

        func stop() {
            queue.async { [weak self] in
                self?.closeSession()
            }
        }

        // MARK: Event

        func event(_ kind: String, _ payload: [String: Any]) {
            // Snapshot the timeline anchors on the *calling* thread so the stamp reflects when the
            // event happened, not when the queue drains it. `t` is the EXACT per-event time
            // (`exactNow` = CACurrentMediaTime - startTime), not the ~4 Hz throttled `clock` the HUD
            // publishes — so two events in one throttle window get distinct `t`s and the JSONL session
            // correlates against a screen recording to the sub-frame. `f` stays the published frame
            // index (frame-grain is fine as a coarse anchor).
            let t = BrunoFrameMonitor.shared.exactNow
            let f = BrunoFrameMonitor.shared.displayFrameIndex

            queue.async { [weak self] in
                self?.append(kind: kind, t: t, f: f, payload: payload)
            }
        }

        // MARK: Queue-confined implementation

        /// Open `<Caches>/BrunoPerf/session-<stamp>.jsonl` and write the header. No-op if already open.
        /// Never throws to the caller: any failure degrades to a no-op session + one os_log warning.
        private func openSession() {
            guard handle == nil else { return }

            let fm = FileManager.default
            guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                Self.log.warning("perflog: no caches directory; logging disabled this session")
                return
            }

            let dir = caches.appendingPathComponent("BrunoPerf", isDirectory: true)
            let url = dir.appendingPathComponent("session-\(Self.timestamp()).jsonl")

            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                guard fm.createFile(atPath: url.path, contents: nil) else {
                    Self.log.warning("perflog: could not create \(url.path, privacy: .public)")
                    return
                }
                let handle = try FileHandle(forWritingTo: url)
                self.handle = handle
                buffer.removeAll(keepingCapacity: true)
                lastFlush = CACurrentMediaTime()

                urlLock.lock()
                _sessionFileURL = url
                urlLock.unlock()

                Self.log.info("perflog: session opened at \(url.path, privacy: .public)")
            } catch {
                Self.log.warning("perflog: open failed: \(error.localizedDescription, privacy: .public)")
                handle = nil
            }

            // Header line: build/version + device so a JSONL file is self-describing for the puller.
            appendHeader()
        }

        private func appendHeader() {
            let bundle = Bundle.main
            let info = bundle.infoDictionary ?? [:]
            let screen = UIScreen.main

            append(kind: "session", t: BrunoFrameMonitor.shared.exactNow, f: BrunoFrameMonitor.shared.displayFrameIndex, payload: [
                "bundleID": bundle.bundleIdentifier ?? "",
                "version": (info["CFBundleShortVersionString"] as? String) ?? "",
                "build": (info["CFBundleVersion"] as? String) ?? "",
                "device": Self.deviceModel(),
                "systemName": UIDevice.current.systemName,
                "systemVersion": UIDevice.current.systemVersion,
                "screenW": Double(screen.bounds.width),
                "screenH": Double(screen.bounds.height),
                "scale": Double(screen.scale),
                "wallClock": ISO8601DateFormatter().string(from: Date()),
            ])
        }

        private func closeSession() {
            flush()
            try? handle?.close()
            handle = nil
            urlLock.lock()
            _sessionFileURL = nil
            urlLock.unlock()
        }

        /// Serialize one event to a JSONL line and buffer it. Reserved keys (`t`/`f`/`kind`) always
        /// win over any same-named payload key so the timeline anchors stay authoritative.
        private func append(kind: String, t: Double, f: Int, payload: [String: Any]) {
            guard handle != nil else { return }

            var object: [String: Any] = [:]
            for (key, value) in payload {
                object[key] = Self.sanitize(value)
            }
            object["t"] = t
            object["f"] = f
            object["kind"] = kind

            guard JSONSerialization.isValidJSONObject(object),
                  var line = try? JSONSerialization.data(withJSONObject: object, options: [])
            else {
                Self.log.warning("perflog: dropped non-serializable event kind=\(kind, privacy: .public)")
                return
            }

            line.append(0x0A) // "\n"
            buffer.append(line)

            let now = CACurrentMediaTime()
            if buffer.count >= Self.flushLineCount * 80 || now - lastFlush >= Self.flushInterval {
                flush()
            }
        }

        private func flush() {
            guard let handle, !buffer.isEmpty else {
                lastFlush = CACurrentMediaTime()
                return
            }
            do {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            } catch {
                Self.log.warning("perflog: write failed: \(error.localizedDescription, privacy: .public)")
            }
            lastFlush = CACurrentMediaTime()
        }

        // MARK: Backgrounding

        /// Flush on background / resign-active so a session survives an app suspend even if `stop()`
        /// never runs (e.g. the user backgrounds while recording).
        private func installObserversIfNeeded() {
            guard !observersInstalled else { return }
            observersInstalled = true
            let center = NotificationCenter.default
            for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willResignActiveNotification] {
                center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                    self?.queue.async { self?.flush() }
                }
            }
        }

        // MARK: Helpers

        /// Coerce a payload value to something JSONSerialization accepts. JSON-safe scalars pass
        /// through; anything else is stringified so a stray value never aborts the whole line.
        private static func sanitize(_ value: Any) -> Any {
            switch value {
            case let v as String: v
            case let v as Bool: v
            case let v as Int: v
            case let v as Double: v
            case let v as Float: Double(v)
            case let v as CGFloat: Double(v)
            case let v as NSNumber: v
            default: String(describing: value)
            }
        }

        private static func timestamp() -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            return formatter.string(from: Date())
        }

        /// Raw machine identifier (e.g. "AppleTV14,1") — more useful than UIDevice.model ("Apple TV").
        private static func deviceModel() -> String {
            var size = 0
            sysctlbyname("hw.machine", nil, &size, nil, 0)
            guard size > 0 else { return UIDevice.current.model }
            var machine = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.machine", &machine, &size, nil, 0)
            return String(cString: machine)
        }
    }
}

// MARK: - Memory footprint

/// Current physical footprint in MB via `task_info(TASK_VM_INFO)` — the same number Xcode's memory
/// gauge reports. Cheap enough to call at ~1 Hz from the frame monitor. Returns 0 on failure.
@inline(__always)
func brunoPerfPhysFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return 0 }
    return Double(info.phys_footprint) / (1024 * 1024)
}

#endif
