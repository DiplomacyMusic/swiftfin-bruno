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
// each carrying its episode number in a `rewatchables-ep:NN` item tag) bucketed into the 11 broad
// BrunoCoreGenre genres and rendered as one shelf per non-empty bucket through the shared
// BrunoCategoryShelves. Each poster shows its "Episode NN" caption (BrunoRewatchablesContentView, via
// the surface-wide showsEpisode flag); each genre shelf's "Show all" opens that genre's full grid
// (DrillStyle.genreGrid). A film appears under EVERY broad genre it matches (intentional, mirroring the
// Genres surface); a film matching none of the 11 buckets is omitted from the broad-genre view (still
// reachable via the collection itself).
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
            } else if viewModel.categories.isEmpty {
                emptyState
            } else {
                BrunoCategoryShelves(
                    categories: viewModel.categories,
                    eyebrow: "The Rewatchables",
                    // "Just the broad genre shelves": no scroll-jump category row, each shelf's "Show all"
                    // reaches its genre grid. Name the Show-all cards with the genre ("Show all · Comedy").
                    showCategoryRow: false,
                    namesShowAllCards: true,
                    // Render each poster's "Episode NN" caption from the rewatchables-ep:NN tag (INV-1:
                    // BrunoRewatchablesContentView is a geometry-faithful clone, row height unchanged).
                    showsEpisode: true,
                    // Branded full-bleed background (the podcast art) instead of a movie hero.
                    staticBackgroundAsset: "RewatchablesHero"
                )
                // Pushed COVER (isTabRoot defaults false) ⇒ BrunoCategoryShelves injects the scrolling
                // BrunoCoverMenuBarRow as its first row, like the Genres / Decades / Curated covers.
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
    private(set) var categories: [BrunoCollectionCategory] = []
    @Published
    private(set) var isLoading = true

    func load(parent: BaseItemDto) async {
        guard let userSession, let parentID = parent.id else {
            isLoading = false
            return
        }
        let client = userSession.client
        let userID = userSession.user.id

        let films = await Self.fetchMembers(client: client, userID: userID, parentID: parentID)
        categories = Self.bucket(films)
        isLoading = false
    }

    /// Bucket the collection's films into the 11 BrunoCoreGenre buckets (in BrunoCoreGenre.all order) by
    /// matching each film's raw .genres against the bucket members. A film lands in EVERY bucket it
    /// matches; empty buckets are dropped. Pure over the fetched set (no RNG; server order preserved
    /// within a bucket), so the surface is stable for a given library.
    private static func bucket(_ films: [BaseItemDto]) -> [BrunoCollectionCategory] {
        BrunoCoreGenre.all.compactMap { core in
            let members = films.filter { film in
                (film.genres ?? []).contains { core.matches($0) }
            }
            guard members.isNotEmpty else { return nil }
            // Synthetic per-bucket category: a label-only boxSet stub (stable unique id per bucket so
            // focus identity holds — INV-2) whose Show-all opens the bucket's portrait grid (.genreGrid).
            return BrunoCollectionCategory(
                boxSet: BaseItemDto(id: "rewatchables-\(core.id)", name: core.title),
                children: members,
                drillStyle: .genreGrid
            )
        }
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
        // .tags carries rewatchables-ep:NN for the poster caption; .genres feeds the bucketing AND the
        // hero child-safety filter (brunoHeroEligible). 300 > 214 so the whole collection lands at once.
        parameters.fields = .MinimumFields + [.genres, .tags]
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
