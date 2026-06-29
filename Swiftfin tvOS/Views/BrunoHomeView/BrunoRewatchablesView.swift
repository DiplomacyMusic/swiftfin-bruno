//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftUI

// Prototype copy is English-only; localization (L10n) is a deferred TODO (see BRUNO_NOTES.md).
// swiftlint:disable hard_coded_display_string

// MARK: - BrunoRewatchablesView (tvOS only)

//
// The Rewatchables drill-in: the favorited "Rewatchables" BoxSet (the films from Bill Simmons' podcast,
// each carrying its episode number in a `rewatchables-ep:NN` item tag) rendered as ONE flat, dense
// portrait grid — the SAME BrunoBoxSetGridView the Directors "Show all" uses — over the branded
// RewatchablesHero backdrop. Each poster shows its "Episode NN" caption (BrunoRewatchablesContentView,
// via the grid's showsEpisode flag). Members are fetched WITH .tags (the caption source); no genre
// bucketing — the whole collection is one grid.
struct BrunoRewatchablesView: View {

    let parent: BaseItemDto

    @StateObject
    private var viewModel = BrunoRewatchablesViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(2)
                    .tint(Color.bruno.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.films.isEmpty {
                emptyState
            } else {
                ZStack {
                    // Branded full-bleed backdrop (the podcast art) as a SIBLING layer behind the
                    // transparent CollectionVGrid — INV-6: not a scroll `.background`. The grid's
                    // UICollectionView has `backgroundColor = nil`, so the backdrop reads through.
                    BrunoAmbientBackground(item: nil, staticAsset: "RewatchablesHero")
                    // Reuse the Directors "Show all" grid as-is: one flat, dense portrait grid of every
                    // rewatchable film, each poster captioned with its "Episode NN" (showsEpisode).
                    BrunoBoxSetGridView(
                        title: "Rewatchables",
                        items: viewModel.films,
                        posterType: .portrait,
                        showsEpisode: true
                    )
                }
            }
        }
        .onFirstAppear {
            Task { await viewModel.load(parent: parent) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("Nothing here yet")
                .font(.brunoDisplay(40, weight: .semibold))
                .foregroundStyle(Color.bruno.fg)
            Text("The Rewatchables collection will appear here.")
                .font(.brunoBody(22))
                .foregroundStyle(Color.bruno.fgMuted)
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - BrunoRewatchablesViewModel

@MainActor
final class BrunoRewatchablesViewModel: ViewModel {

    @Published
    private(set) var films: [BaseItemDto] = []
    @Published
    private(set) var isLoading = true

    func load(parent: BaseItemDto) async {
        guard let userSession, let parentID = parent.id else {
            isLoading = false
            return
        }
        let client = userSession.client
        let userID = userSession.user.id

        films = await Self.fetchMembers(client: client, userID: userID, parentID: parentID)
        isLoading = false
    }

    private nonisolated static func fetchMembers(
        client: JellyfinClient,
        userID: String,
        parentID: String
    ) async -> [BaseItemDto] {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.parentID = parentID
        parameters.includeItemTypes = [.movie]
        // .tags carries rewatchables-ep:NN for the per-poster "Episode NN" caption. 300 > 214 so the
        // whole collection lands in one page.
        parameters.fields = .MinimumFields + [.tags]
        parameters.enableUserData = true
        parameters.limit = 300
        do {
            let response = try await client.send(Paths.getItems(parameters: parameters))
            return response.value.items ?? []
        } catch {
            return []
        }
    }
}

// MARK: - NavigationRoute

extension NavigationRoute {

    @MainActor
    static func brunoRewatchables(parent: BaseItemDto) -> NavigationRoute {
        NavigationRoute(
            id: "bruno-rewatchables-\(parent.id ?? parent.displayTitle)"
        ) {
            BrunoRewatchablesView(parent: parent)
        }
    }
}
