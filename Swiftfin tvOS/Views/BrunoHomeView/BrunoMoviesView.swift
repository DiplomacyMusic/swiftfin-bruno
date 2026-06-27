//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// Prototype copy is English-only; localization (L10n) is a deferred TODO (see BRUNO_NOTES.md).
// swiftlint:disable hard_coded_display_string

// MARK: - BrunoMoviesView (tvOS only)

//
// The Movies tab root. Rather than a flat A–Z grid, the Movies tab IS the genre-browse surface:
// it resolves the "Genres" group BoxSet from the shared library snapshot and hands it to
// BrunoGenresView (hero + core-genre pills + a shelf per sub-genre). The full A–Z grid still
// exists, reached lazily via the trailing "All Movies" pill (it only fetches when pushed).
//
// Thin pass-through ONLY: no ambient ZStack, no .ignoresSafeArea, no .safeAreaInset of its own —
// BrunoCategoryShelves (under BrunoGenresView) already owns all of that, and MainTabView supplies
// the menu bar to tab roots for free. Adding chrome here reintroduces the menu-bar drift bug.
struct BrunoMoviesView: View {

    @StateObject
    private var viewModel = BrunoMoviesViewModel()

    @Router
    private var router

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(2)
                    .tint(Color.bruno.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let group = viewModel.genresGroup {
                BrunoGenresView(
                    parent: group,
                    core: nil,
                    isTabRoot: true,
                    onShowAll: { router.route(to: .brunoMoviesGrid) }
                )
            } else {
                // No Genres group (or an empty/failed snapshot): fall back to the A–Z movie grid so
                // the tab is never blank. Still the Movies TAB ROOT → inject the scrolling menu bar.
                BrunoMediaView(itemType: .movie, heroEyebrow: "Featured Film", isTabRoot: true)
            }
        }
        .onFirstAppear {
            Task { await viewModel.load() }
        }
    }
}

// MARK: - BrunoMoviesViewModel

@MainActor
final class BrunoMoviesViewModel: ViewModel {

    @Published
    private(set) var genresGroup: BaseItemDto?
    @Published
    private(set) var isLoading = true

    func load() async {
        guard let userSession else {
            isLoading = false
            return
        }
        // Reuse the snapshot Home/Collections already loaded (shared cache, 5 min TTL).
        let snapshot = await BrunoLibrarySnapshot.loadShared(
            client: userSession.client,
            userID: userSession.user.id
        )
        // .isEmpty also covers loadShared's `.empty` failure return (snapshot is not Equatable).
        if !snapshot.isEmpty {
            genresGroup = snapshot.favoriteGroupBoxSets.first { $0.name?.lowercased() == "genres" }
        }
        isLoading = false
    }
}

// MARK: - NavigationRoute

extension NavigationRoute {

    /// The lazy A–Z "All Movies" grid, pushed from the Movies tab's trailing pill. As a pushed cover
    /// (isTabRoot defaults false), BrunoMediaView injects the scrolling BrunoCoverMenuBarRow as its
    /// first row — no pinned bar (BrunoMediaView loads on first appear, so the full library is only
    /// fetched when this pill is selected).
    @MainActor
    static var brunoMoviesGrid: NavigationRoute {
        NavigationRoute(id: "bruno-movies-grid") {
            BrunoMediaView(itemType: .movie, heroEyebrow: "Featured Film")
        }
    }

    /// The lazy A–Z "All TV" grid, pushed from a "Show all TV" terminal-footer pill (Home). Same
    /// cover/menu-bar contract as the movies grid (scrolling BrunoCoverMenuBarRow via BrunoMediaView);
    /// BrunoMediaView loads on first appear.
    @MainActor
    static var brunoTVGrid: NavigationRoute {
        NavigationRoute(id: "bruno-tv-grid") {
            BrunoMediaView(itemType: .series, heroEyebrow: "Featured Series")
        }
    }
}
