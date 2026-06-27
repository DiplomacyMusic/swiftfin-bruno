//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Factory
import SwiftUI

// MARK: - BrunoCoverMenuBarRow (tvOS only)

//
// The Bruno top menu bar packaged as a SCROLLING ROW for a pushed hero-banner COVER (Decades /
// pushed Genres / All-Movies / All-TV grids). It is the first row of the cover's LazyVStack, above
// the hero, and scrolls up and off-screen like every other shelf — just like the tab-root bar
// (BrunoScrollingMenuBar). Covers no longer PIN their bar.
//
// Why a row, not a pinned overlay: pinning put two focusables (the pills + the hero `Button`) in the
// same vertical region, which the tvOS focus engine resolves badly. As its own row there is one
// focusable per vertical region, so UP/DOWN are clean vertical moves (shelf ↔ hero ↔ bar). The row
// occupies the barHeight the old pinned-bar inset used to reserve, so the hero geometry is unchanged.
//
// Difference from the tab-root bar (BrunoScrollingMenuBar): a cover is presented as a separate hosting
// controller that does NOT inherit the environment `TabCoordinator`, so the tab list + selection come
// from the @Injected `brunoTabBridge`. And pressing a pill DISMISSES the cover and THEN switches the
// tab (BrunoTabBridge + Router), so you land on the chosen tab's root rather than switching the tab
// hidden behind the cover.
struct BrunoCoverMenuBarRow: View {

    @Injected(\.brunoTabBridge)
    private var bridge

    @Router
    private var router

    @FocusState
    private var barFocus: String?

    var body: some View {
        Group {
            if let coordinator = bridge.coordinator {
                BrunoMenuBar(
                    tabs: coordinator.tabs.map(\.item),
                    selection: Binding(
                        get: { coordinator.selectedTabID },
                        set: { newID in
                            // Dismiss the cover first, then switch — so we land on the chosen tab's
                            // root, not the tab sitting behind the cover (BrunoTabBridge notes).
                            router.dismiss()
                            if let newID { coordinator.selectedTabID = newID }
                        }
                    ),
                    focus: $barFocus
                )
            } else {
                // The bridge hasn't resolved yet — reserve the row's height so the LazyVStack layout
                // (and the hero geometry below it) doesn't shift when the bar appears.
                Color.clear.frame(height: BrunoMenuBar.barHeight)
            }
        }
        .frame(height: BrunoMenuBar.barHeight) // INV-1: fixed height, independent of focus/content
        .focusSection()
    }
}
