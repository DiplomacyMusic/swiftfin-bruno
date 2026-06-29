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

    /// Optional reporter: mirrors whether THIS bar holds focus up to the host (Home uses it to gate its
    /// Menu-to-exit behaviour — Menu on the bar = "at the top"). nil for tabs that don't need it.
    private let barFocused: Binding<Bool>?

    /// Tab-root mode: the live coordinator carries the tab list + current selection. EnvironmentObject
    /// (not @Injected) because each tab root already receives it via `.environmentObject(tabCoordinator)`.
    @EnvironmentObject
    private var tabCoordinator: TabCoordinator

    /// Owned by this wrapper — there is no pinned bar for MainTabView to drive focus onto anymore, so the
    /// focus binding lives here instead of being threaded down from the container.
    @FocusState
    private var barFocus: String?

    /// True only for the ACTIVE tab's bar (MainTabView injects this per tab). Gates the pending-focus
    /// claim so exactly one bar — the newly-selected tab's — grabs focus after a pill press.
    @Environment(\.brunoTabIsActive)
    private var isActive

    /// TAB-ROOT mode (the only mode used today): the tab list + selection come from the environment
    /// `TabCoordinator`. Inject as the first row of a tab root's `LazyVStack`.
    init(barFocused: Binding<Bool>? = nil) {
        self.explicitTabs = nil
        self.explicitSelection = nil
        self.barFocused = barFocused
    }

    /// EXPLICIT mode (seam for a future cover mode): pass the tab list + a selection binding directly,
    /// for surfaces that don't inherit the environment coordinator (e.g. fullScreenCovers). Not used yet.
    init(tabs: [TabItem], selection: Binding<String?>) {
        self.explicitTabs = tabs
        self.explicitSelection = selection
        self.barFocused = nil
    }

    /// Selection binding for the pills. In tab-root mode the setter (which fires ONLY on a pill PRESS —
    /// pills never switch on focus) also records `pendingBarFocus`, the one-shot intent the newly-active
    /// tab's bar consumes to keep focus on the selected pill instead of falling to the hero.
    private var selectionBinding: Binding<String?> {
        if let explicitSelection { return explicitSelection }
        return Binding(
            get: { tabCoordinator.selectedTabID },
            set: { newID in
                // Record the intent only on an actual tab CHANGE (selectedTabID is still the old value
                // here), so re-pressing the current tab's pill leaves no stale pending claim behind.
                if let newID, newID != tabCoordinator.selectedTabID { tabCoordinator.pendingBarFocus = newID }
                tabCoordinator.selectedTabID = newID
            }
        )
    }

    /// Consume the one-shot pending-focus intent and claim it on the matching pill — deferred one runloop
    /// so the pill is enabled + laid out (the new tab is being un-`.disabled()` in this same transaction;
    /// a synchronous set would be dropped). Mirrors BrunoHomeView's `Task { @MainActor in homeFocus … }`.
    private func claimPendingBarFocus(active: Bool) {
        guard active, let target = tabCoordinator.pendingBarFocus else { return }
        tabCoordinator.pendingBarFocus = nil
        Task { @MainActor in barFocus = target }
    }

    var body: some View {
        BrunoMenuBar(
            tabs: explicitTabs ?? tabCoordinator.tabs.map(\.item),
            selection: selectionBinding,
            focus: $barFocus
        )
        .frame(height: BrunoMenuBar.barHeight) // INV-1: fixed height, independent of focus/content
        .focusSection()
        // Claim the pending pill focus when THIS tab becomes active: onChange covers switching back to an
        // already-mounted tab; onAppear covers a first-time lazy mount (isActive already true, no change).
        .onChange(of: isActive) { _, nowActive in claimPendingBarFocus(active: nowActive) }
        // In-tab claim: cold launch + Back-to-Top + Menu-from-shelves set pendingBarFocus while THIS tab
        // is already active + mounted, so neither onAppear nor onChange(isActive) re-fires — observe the
        // intent directly. Race-free on a tab switch: onChange sees the post-render isActive, so only the
        // active bar's `guard active` passes, and claimPendingBarFocus nil-clears the one-shot (idempotent).
        .onChange(of: tabCoordinator.pendingBarFocus) { _, _ in claimPendingBarFocus(active: isActive) }
        .onAppear { claimPendingBarFocus(active: isActive) }
        // Mirror this bar's focus up to the host (Home's Menu-to-exit gate). barFocus is nil ⇔ unfocused.
        .onChange(of: barFocus) { _, focused in barFocused?.wrappedValue = (focused != nil) }
    }
}
