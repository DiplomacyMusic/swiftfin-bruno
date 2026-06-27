//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if DEBUG

import ObjectiveC
import OSLog
import UIKit

// MARK: - Bruno raw-input capture (DEBUG only)

//
// Captures raw remote-button presses + HOLD durations into the on-disk perf log (BrunoPerfLog) so a
// recorded session can prove the exact "held N ms, focus advanced K rows, then stalled while still
// held" failure mode — by correlating these `input` events against the `nav`/`fps`/`mem` events that
// already share the same timeline (`t`/`f`).
//
// WHY a UIPress hook and not GameController:
//   On the SIMULATOR the "remote" is driven by the host keyboard / the macOS Remote app, routed
//   through UIKit's UIPress pipeline. `GCController` only sees a real paired controller, so it is blind
//   to sim input. Observing `UIPress` events captures both the sim and a real Siri Remote.
//
// HOW the hook stays NON-CONSUMING:
//   We method-swizzle `-[UIWindow sendEvent:]` (the point "called by UIApplication to dispatch events
//   to views inside the window"). The replacement only READS `event.allPresses`, then calls THROUGH to
//   the original implementation unchanged. Because the original dispatch runs verbatim, focus,
//   scrolling and every gesture behave exactly as before — we add an observer, we never intercept.
//
// Everything is DEBUG-gated and inert unless `BrunoPerfLog.isEnabled`. The swizzle is installed lazily
// (once) the first time perf logging starts and is left in place; when logging stops, the replacement
// short-circuits on the `isEnabled` check and is effectively free (one bool read per UI event).

enum BrunoInputMonitor {

    private static let log = Logger(subsystem: "org.jellyfin.swiftfin.bruno", category: "input")

    /// Per-pressType `.began` time (seconds since the frame monitor started), so an `.ended`/`.cancelled`
    /// can report the hold duration. Keyed by the raw `UIPress.PressType` rawValue. Touched only on the
    /// main thread (UIKit event dispatch is main-thread), so a plain dictionary is race-free.
    private static var downTimes: [Int: Double] = [:]

    /// Whether `installSwizzleIfNeeded()` has run. One-shot; the swizzle is never reverted (the
    /// replacement is inert while `!isEnabled`, so leaving it installed costs one bool read per event).
    private static var installed = false

    // MARK: Lifecycle (called from BrunoPerfLog.start/stop)

    /// Arm input capture. Installs the swizzle the first time it's called; subsequent calls are no-ops.
    /// Safe to call off the perf-logging toggle. MUST be on the main thread (it touches UIKit metadata);
    /// `BrunoPerfLog.start()` is invoked from the SwiftUI `sync()` path, which is main.
    static func start() {
        installSwizzleIfNeeded()
    }

    /// Disarm. We don't un-swizzle (reverting is fragile and pointless here) — clearing the in-flight
    /// down-times is enough, and the replacement no-ops on `!isEnabled`.
    static func stop() {
        downTimes.removeAll(keepingCapacity: true)
    }

    // MARK: Swizzle install

    private static func installSwizzleIfNeeded() {
        guard !installed else { return }
        installed = true

        let cls = UIWindow.self
        let selector = #selector(UIWindow.sendEvent(_:))

        guard let originalMethod = class_getInstanceMethod(cls, selector) else {
            log.warning("input: could not find -[UIWindow sendEvent:]; input capture disabled")
            return
        }

        // Capture the original IMP so the replacement can call THROUGH to it (non-consuming).
        typealias SendEventIMP = @convention(c) (UIWindow, Selector, UIEvent) -> Void
        let originalIMP = method_getImplementation(originalMethod)
        let originalFn = unsafeBitCast(originalIMP, to: SendEventIMP.self)

        let block: @convention(block) (UIWindow, UIEvent) -> Void = { window, event in
            // Observe first (cheap, bool-gated), then ALWAYS run the original dispatch unchanged.
            if BrunoPerfLog.isEnabled, let pressesEvent = event as? UIPressesEvent {
                BrunoInputMonitor.handle(pressesEvent)
            }
            originalFn(window, selector, event)
        }

        let newIMP = imp_implementationWithBlock(block)
        method_setImplementation(originalMethod, newIMP)
        log.info("input: -[UIWindow sendEvent:] swizzled for non-consuming press capture")
    }

    // MARK: Press handling

    /// Inspect every press in the event and emit `input` events. On `.began` record the down-time and
    /// emit `phase:"down"`; on `.ended`/`.cancelled` emit `phase:"up"` with the elapsed `holdMs`.
    /// `.changed`/`.stationary` are ignored — the key signal is down-time, up-time, hold duration.
    /// Main-thread only (UIKit dispatch), so `downTimes` access is race-free.
    private static func handle(_ event: UIPressesEvent) {
        let now = BrunoFrameMonitor.shared.exactNow
        for press in event.allPresses {
            let key = press.type.rawValue
            let name = name(for: press.type)
            switch press.phase {
            case .began:
                downTimes[key] = now
                BrunoPerfLog.event("input", ["phase": "down", "button": name])
            case .ended, .cancelled:
                let holdMs = downTimes[key].map { (now - $0) * 1000 } ?? 0
                downTimes[key] = nil
                BrunoPerfLog.event("input", ["phase": "up", "button": name, "holdMs": holdMs])
            case .changed, .stationary:
                break
            @unknown default:
                break
            }
        }
    }

    /// Map a `UIPress.PressType` to the short button name the perf log records.
    private static func name(for type: UIPress.PressType) -> String {
        switch type {
        case .upArrow: "up"
        case .downArrow: "down"
        case .leftArrow: "left"
        case .rightArrow: "right"
        case .select: "select"
        case .menu: "menu"
        case .playPause: "playPause"
        @unknown default: "other"
        }
    }
}

#endif
