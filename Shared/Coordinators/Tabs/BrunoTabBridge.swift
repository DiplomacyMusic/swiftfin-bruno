//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Factory
import SwiftUI

// MARK: - BrunoTabBridge

//
// Bridges the tvOS custom top menu bar into pushed hero-banner surfaces (Decades / Genres). Those are
// presented as `fullScreenCover`s, which are separate hosting controllers that do NOT inherit
// MainTabView's `TabCoordinator` from the environment — so a menu bar rendered inside them otherwise
// has no way to read the tab list / current selection or switch tabs.
//
// MainTabView publishes a LIVE WEAK reference to its coordinator here on appear; the in-cover bar reads
// the tabs + selection through it and switches tabs via it (after dismissing the cover). Weak + a live
// reference (not a singleton TabCoordinator) means there is no per-session state to go stale across
// sign-out: when MainTabView goes away the reference simply becomes nil.
@MainActor
final class BrunoTabBridge: ObservableObject {

    weak var coordinator: TabCoordinator?

    // Constructed by Factory's nonisolated closure; the weak ref defaults to nil so no isolated state
    // is touched here. All `coordinator` access happens from @MainActor call sites.
    nonisolated init() {}
}

extension Container {

    var brunoTabBridge: Factory<BrunoTabBridge> {
        self { BrunoTabBridge() }
            .singleton
    }
}
