//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// MARK: - BrunoScrollingMenuBar (tvOS only)

//
// The Bruno top menu bar packaged as a SCROLLING ROW (not a pinned overlay): the first real row of each
// tab's LazyVStack, above the hero. It scrolls up and off-screen like every other shelf, then reappears
// at the top — replacing MainTabView's old pinned `ZStack(alignment: .top)` peer.
//
// Why a row, not an overlay on the hero: an overlay puts two focusables (the pills + the hero `Button`)
// in the same vertical region, which the tvOS focus engine resolves badly. As its own row there is one
// focusable per vertical region, so UP/DOWN are clean vertical moves (shelf ↔ hero ↔ bar).
//
// The component is a thin wrapper around BrunoMenuBar:
//   • owns its OWN `@FocusState barFocus` (each tab's bar is independent — there is no pinned bar whose
//     focus MainTabView needs to drive anymore; Menu at a tab root falls through to the system normally);
//   • applies `.frame(height: BrunoMenuBar.barHeight)` (INV-1: fixed height, independent of focus/content)
//     and `.focusSection()`;
//   • DOES NOT apply `.zIndex` — the call site does that, so the bar row paints on top of the hero's
//     upward backdrop spill (the hero is the next row and bleeds UP into this row's region).
//
// Selection switches on Select (press) only, never on focus — traversing the bar must not switch tabs
// (BrunoMenuBar already enforces this; this wrapper just supplies the binding).
struct BrunoScrollingMenuBar: View {

    /// The tabs to render. nil ⇒ TAB-ROOT mode: read the list from the environment `TabCoordinator`
    /// (tab-root content always has it injected by MainTabView). Non-nil ⇒ EXPLICIT mode (a future
    /// "cover mode" that has no coordinator in environment can pass the list + a selection binding
    /// directly — covers are presented as separate hosting controllers that don't inherit the env
    /// coordinator). Only tab-root mode is used today.
    private let explicitTabs: [TabItem]?

    /// Selection binding in EXPLICIT mode. Ignored in tab-root mode (the coordinator's binding is used).
    private let explicitSelection: Binding<String?>?

    /// When true, the BRUNO wordmark is overlaid at the leading edge, vertically centered with the pills.
    /// Home enables it (matching where the wordmark lived before the un-pin); other tabs leave it off.
    private let showsWordmark: Bool

    /// Tab-root mode: the live coordinator carries the tab list + current selection. EnvironmentObject
    /// (not @Injected) because each tab root already receives it via `.environmentObject(tabCoordinator)`.
    @EnvironmentObject
    private var tabCoordinator: TabCoordinator

    /// Owned by this wrapper — there is no pinned bar for MainTabView to drive focus onto anymore, so the
    /// focus binding lives here instead of being threaded down from the container.
    @FocusState
    private var barFocus: String?

    /// TAB-ROOT mode (the only mode used today): the tab list + selection come from the environment
    /// `TabCoordinator`. Inject as the first row of a tab root's `LazyVStack`.
    init(showsWordmark: Bool = false) {
        self.explicitTabs = nil
        self.explicitSelection = nil
        self.showsWordmark = showsWordmark
    }

    /// EXPLICIT mode (seam for a future cover mode): pass the tab list + a selection binding directly,
    /// for surfaces that don't inherit the environment coordinator (e.g. fullScreenCovers). Not used yet.
    init(tabs: [TabItem], selection: Binding<String?>, showsWordmark: Bool = false) {
        self.explicitTabs = tabs
        self.explicitSelection = selection
        self.showsWordmark = showsWordmark
    }

    var body: some View {
        BrunoMenuBar(
            tabs: explicitTabs ?? tabCoordinator.tabs.map(\.item),
            selection: explicitSelection ?? $tabCoordinator.selectedTabID,
            focus: $barFocus
        )
        .frame(height: BrunoMenuBar.barHeight) // INV-1: fixed height, independent of focus/content
        .focusSection()
        // BRUNO wordmark on the menu line: leading, vertically centered with the pills (pills stay
        // centered via BrunoMenuBar's maxWidth frame). Home-only via showsWordmark.
        .overlay(alignment: .leading) {
            if showsWordmark {
                HStack(spacing: 8) {
                    // swiftlint:disable:next hard_coded_display_string
                    Text("BRUNO")
                        .font(.brunoDisplay(40, weight: .bold))
                        .tracking(6)
                        .foregroundStyle(Color.bruno.fg)
                    Circle()
                        .fill(Color.bruno.accent)
                        .frame(width: 12, height: 12)
                }
                .padding(.leading, 50)
                // Optical nudge onto the pills' centerline (the capsule floats slightly high via
                // BrunoMenuBar's top:8/bottom:14). Tune on the sim if it reads off.
                .padding(.bottom, 6)
            }
        }
    }
}
