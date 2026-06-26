//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Factory
import SwiftUI

// MARK: - BrunoHeroMenuBar

//
// Pins the same custom top menu bar (BrunoMenuBar) onto a pushed hero-banner surface (Decades /
// Genres). Those surfaces are presented as fullScreenCovers OVER the tab bar, so MainTabView's
// safeAreaInset bar is occluded — this re-creates it inside the cover.
//
// Same shape as MainTabView's bar: `safeAreaInset(.top)` so the hero backdrop bleeds to the physical
// top behind the pills, both regions `focusSection()` so UP reaches the bar / DOWN returns to content,
// and `prefersDefaultFocus` so the cover opens with focus on the hero (not the bar). Differences from
// the tab-root bar:
//   • No `onExitCommand` override — in a cover, Menu should DISMISS (the natural back), which it does
//     for free; the bar stays reachable via UP.
//   • Pressing a pill dismisses the cover and THEN switches the tab (via BrunoTabBridge), so you land
//     on the chosen tab's root rather than switching the tab hidden behind the cover.
private struct BrunoHeroMenuBar: ViewModifier {

    @Injected(\.brunoTabBridge)
    private var bridge

    @Router
    private var router

    @FocusState
    private var barFocus: String?

    @Namespace
    private var namespace

    func body(content: Content) -> some View {
        content
            .focusSection()
            .prefersDefaultFocus(in: namespace)
            .safeAreaInset(edge: .top, spacing: 0) {
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
                    .focusSection()
                }
            }
            .focusScope(namespace)
    }
}

extension View {

    /// Pin the Bruno top menu bar onto a pushed hero-banner surface (see BrunoHeroMenuBar). tvOS only.
    func brunoHeroMenuBar() -> some View {
        modifier(BrunoHeroMenuBar())
    }
}
