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

// MARK: - BrunoCollectionsView (tvOS only)

//
// The Collections tab, redesigned from a flat BoxSet grid into per-category shelves (roadmap §3):
// a category row across the top, then one capped shelf per curated group (Directors, Decades,
// Studios, …). Genres/Decades "Show all" drills into a further shelf-per-sub-group view (§4);
// the rest open the stock full grid. Rendering is delegated to the shared BrunoCategoryShelves.
struct BrunoCollectionsView: View {

    @StateObject
    private var viewModel = BrunoCollectionsViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(2)
                    .tint(Color.bruno.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.categories.isEmpty {
                emptyState
            } else {
                BrunoCategoryShelves(
                    categories: viewModel.categories,
                    eyebrow: "Browse the Library",
                    featured: brunoFeaturedItem(in: viewModel.categories),
                    heroEyebrow: "Featured",
                    // Collections TAB ROOT → inject the scrolling menu bar as the first row.
                    isTabRoot: true
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onFirstAppear {
            Task { await viewModel.load() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No collections yet")
                .font(.brunoDisplay(40, weight: .semibold))
                .foregroundStyle(Color.bruno.fg)
            Text("Curated collections from this server will appear here.")
                .font(.brunoBody(22))
                .foregroundStyle(Color.bruno.fgMuted)
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - BrunoCollectionsViewModel

@MainActor
final class BrunoCollectionsViewModel: ViewModel {

    @Published
    private(set) var categories: [BrunoCollectionCategory] = []
    @Published
    private(set) var isLoading = true

    func load() async {
        guard let userSession else {
            isLoading = false
            return
        }

        let client = userSession.client
        let userID = userSession.user.id
        // Reuse the snapshot Home just loaded (shared cache) instead of refetching the whole
        // library on every Home -> Collections navigation.
        let snapshot = await BrunoLibrarySnapshot.loadShared(client: client, userID: userID)

        // The full group-tile set (Directors, Decades, …, plus the synthetic Boxed Sets), built and
        // rank-ordered from the shared snapshot. `fromSnapshot` now surfaces Boxed Sets from the
        // snapshot's cached `franchiseBoxSets`, so the Collections hub, the Home footer, and the Home
        // "Browse the Collection" shelf are byte-identical (same cards, same order, same destinations).
        categories = BrunoCollectionCategory.fromSnapshot(snapshot)
        isLoading = false
    }
}
