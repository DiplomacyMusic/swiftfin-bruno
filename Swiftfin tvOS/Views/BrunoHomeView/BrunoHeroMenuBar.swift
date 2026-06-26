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
// Same shape as MainTabView's bar: the cover content insets its scroll plane below the bar with a REAL
// padding (`brunoBelowMenuBar()` inside BrunoCategoryShelves) so its focus section is a non-overlapping
// peer and UP reaches the bar / DOWN returns to content, the ambient bleeds full-screen behind the pills,
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
        // Same peer-sibling shape as MainTabView: content + bar are focus peers under one `.focusScope`, the
        // bar floating over the cover's full-bleed ambient via `ZStack(alignment: .top)`. The non-overlap
        // that lets UP reach the bar lives in the cover's CONTENT: BrunoCategoryShelves wraps its scroll
        // content in `brunoBelowMenuBar()` (a REAL padding inset + focus section), so the focusable cells are
        // a peer strictly below the bar — we must NOT re-inset or re-section here (a `safeAreaInset` left the
        // frame full-screen and overlapped the bar, the UP bug). We only overlay the bar and bias default
        // focus to the content. No onExitCommand — in a cover, Menu dismisses (the natural back).
        ZStack(alignment: .top) {
            content
                .prefersDefaultFocus(in: namespace)

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
                }
            }
            .frame(height: BrunoMenuBar.barHeight, alignment: .top)
            .focusSection()
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
