//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// MARK: - Bruno debug overlay — public instrumentation API

//
// These are the ONLY entry points call sites use. They compile to the real DEBUG engine
// (BrunoDebugCore / BrunoDebugOverlayView) or to inert pass-throughs in release, so production
// code carries zero cost and instrumentation lines need no `#if DEBUG` at the call site.

extension View {

    /// Inject the debug HUD above all app content. Wrap the root once per platform; the panels are
    /// individually toggled from Settings and the frame monitor only runs while one is on.
    func brunoDebugOverlay() -> some View {
        #if DEBUG
        return modifier(BrunoDebugOverlayModifier())
        #else
        return self
        #endif
    }

    /// Count this view's `body` re-evaluations — the "redraws as a result of navigation" signal.
    /// Cheap: a single bool check when the nav overlay is off.
    func brunoDebugRedraw(_ name: String) -> some View {
        #if DEBUG
        if BrunoDebugFlags.redrawEnabled {
            BrunoFrameMonitor.shared.bumpRedraw(name)
        }
        #endif
        return self
    }

    /// Track this view's vertical movement (the layout "graphic math" of a nav scroll) and
    /// attribute coincident frame drags to navigation.
    func brunoDebugLayout(_ name: String) -> some View {
        #if DEBUG
        return modifier(BrunoDebugLayoutModifier(name: name))
        #else
        return self
        #endif
    }

    /// Log a discrete nav-input event when `isFocused` becomes true.
    func brunoDebugNavFocus(_ name: String, isFocused: Bool) -> some View {
        #if DEBUG
        return modifier(BrunoDebugNavFocusModifier(name: name, isFocused: isFocused))
        #else
        return self
        #endif
    }

    /// Watch a height-pinned shelf row (INV-1) for a MEASURED height that deviates from the pinned
    /// `expected` value by more than 1pt — the "scroll/draw math conflict" the pin exists to kill.
    /// Emits a `conflict` perf event on each new deviation (throttled so a stable row never spams).
    /// Apply at the pinning site, passing the SAME value used in `.frame(height:)`. Release-inert no-op.
    func brunoPerfHeightWatch(site: String, expected: CGFloat) -> some View {
        #if DEBUG
        return modifier(BrunoPerfHeightWatchModifier(site: site, expected: expected))
        #else
        return self
        #endif
    }

    /// Count this view as one realized cell-content view: +1 on appear, −1 on disappear, into
    /// `BrunoPerfCounts.cells` (sampled into the `counts` perf event ~1 Hz). Apply to a cell's content
    /// ROOT (e.g. `BrunoLabelArtCard.body` / `PosterButton.body`) so the figure tracks how many cells
    /// are actually realized across surfaces during a hitch. Release-inert no-op.
    func brunoPerfCell() -> some View {
        #if DEBUG
        return modifier(BrunoPerfCellModifier())
        #else
        return self
        #endif
    }
}

#if DEBUG

/// Increments the live cell-content counter on appear and decrements on disappear. The counter is an
/// unfair-lock-guarded Int in `BrunoPerfCounts`, so it's correct even though appear/disappear and the
/// ~1 Hz sampler touch it from different contexts. No state and no work beyond the two counter calls,
/// so an unrecorded session pays only the appear/disappear bookkeeping (which would happen anyway).
struct BrunoPerfCellModifier: ViewModifier {

    func body(content: Content) -> some View {
        content
            .onAppear { BrunoPerfCounts.cellAppeared() }
            .onDisappear { BrunoPerfCounts.cellDisappeared() }
    }
}

#endif

/// Mirror a view's mounted-shelf-window size into `BrunoPerfCounts.shelves` so the frame monitor can
/// sample it into the `counts` perf event. Free function (not a modifier) so it's callable from an
/// `onAppear` / `onChange` closure WITHOUT adding an `init` to the calling view (the F5 trap). Compiles
/// to a no-op in release, so `BrunoCategoryShelves` (a release-built view) can call it unconditionally.
@inline(__always)
func brunoPerfSetShelfCount(_ count: Int) {
    #if DEBUG
    BrunoPerfCounts.shelves = count
    #endif
}
