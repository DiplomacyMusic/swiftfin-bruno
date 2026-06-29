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

// MARK: - BrunoEbertView (tvOS only)

//
// The Ebert drill-in: an "Ebert Thumbs Up"/"Down" curated BoxSet rendered as the cinematic item-detail
// shape — a tall hero band (the Roger Ebert photo) that scrolls away under a descending blur, with a
// dense portrait grid of every film beneath it, each captioned with its star rating
// (BrunoEbertContentView). A clone of BrunoRewatchablesView, with two differences: the grid is ordered by
// Ebert rating (Thumbs Up highest-first, Thumbs Down lowest-first — `ascending`), and a "Browse by" genre
// pill row sub-filters the in-memory members by tagged TMDB genre (added in a later step).
struct BrunoEbertView: View {

    let parent: BaseItemDto

    /// Lowest-rating-first when true (the Thumbs Down shelf), highest-first when false (Thumbs Up).
    /// Derived from the BoxSet name so a single route serves both shelves.
    private var ascending: Bool {
        parent.displayTitle.lowercased().contains("down")
    }

    @StateObject
    private var viewModel = BrunoEbertViewModel()

    @Router
    private var router

    // 7-up portrait, matching the stock library / Rewatchables grid cell scale.
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: EdgeInsets.edgePadding),
        count: 7
    )

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
                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onFirstAppear {
            Task { await viewModel.load(parent: parent, ascending: ascending) }
        }
    }

    private var content: some View {
        GeometryReader { proxy in
            ZStack {
                // Full-bleed brand backdrop (the Roger Ebert photo) — the same image the Ebert curated
                // tiles use (BrunoCategoryTile: "ebert" → Curated02).
                Image("Curated02")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                            .frame(height: proxy.size.height - 150)
                            .padding(.bottom, 50)

                        grid
                    }
                    // The same BlurView(.dark) + descending gradient-mask as Rewatchables / the detail
                    // page: as the grid scrolls up the hero blurs and its colors descend behind the
                    // posters. (Scroll-coupled `.background` blur — the INV-6 carve-out Studios takes.)
                    .background {
                        BlurView(style: .dark)
                            .mask {
                                VStack(spacing: 0) {
                                    LinearGradient(gradient: Gradient(stops: [
                                        .init(color: .white, location: 0),
                                        .init(color: .white.opacity(0.7), location: 0.4),
                                        .init(color: .white.opacity(0), location: 1),
                                    ]), startPoint: .bottom, endPoint: .top)
                                        .frame(height: proxy.size.height - 150)

                                    Color.white
                                }
                            }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    // The shelf title, bottom-left over the backdrop ("Ebert Thumbs Up" / "Ebert Thumbs Down").
    private var header: some View {
        VStack(alignment: .leading) {
            Spacer()
            Text(parent.displayTitle)
                .font(.brunoDisplay(72, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 50)
    }

    // Portrait posters, 7 across, each captioned with its Ebert star rating — laid out in a LazyVGrid so
    // they scroll inside the cinematic ScrollView beneath the hero band.
    private var grid: some View {
        LazyVGrid(columns: columns, spacing: EdgeInsets.edgePadding) {
            ForEach(viewModel.films, id: \.id) { item in
                PosterButton(item: item, type: .portrait) {
                    router.route(to: .item(item: item))
                } label: {
                    BrunoEbertContentView(item: item)
                }
            }
        }
        .padding(.horizontal, EdgeInsets.edgePadding)
        .padding(.bottom, 50)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("Nothing here yet")
                .font(.brunoDisplay(40, weight: .semibold))
                .foregroundStyle(Color.bruno.fg)
            Text("This Ebert collection will appear here.")
                .font(.brunoBody(22))
                .foregroundStyle(Color.bruno.fgMuted)
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - BrunoEbertViewModel

@MainActor
final class BrunoEbertViewModel: ViewModel {

    @Published
    private(set) var films: [BaseItemDto] = []
    @Published
    private(set) var isLoading = true

    func load(parent: BaseItemDto, ascending: Bool) async {
        guard let userSession, let parentID = parent.id else {
            isLoading = false
            return
        }
        let client = userSession.client
        let userID = userSession.user.id

        let members = await Self.fetchMembers(client: client, userID: userID, parentID: parentID)
        // Sort ONCE here (not per body pass) by Ebert rating; the pill filter downstream only filters,
        // preserving this order.
        films = BrunoEbert.ordered(members, ascending: ascending)
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
        // .tags carries ebert-stars:<n> for the caption + ordering; .genres feeds the "Browse by" pills.
        // 1000 > the largest Ebert BoxSet (Thumbs Up ~559) so the whole collection lands in one page.
        parameters.fields = .MinimumFields + [.tags, .genres]
        parameters.enableUserData = true
        parameters.limit = 1000
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
    static func brunoEbert(parent: BaseItemDto) -> NavigationRoute {
        NavigationRoute(
            id: "bruno-ebert-\(parent.id ?? parent.displayTitle)"
        ) {
            BrunoEbertView(parent: parent)
        }
    }
}
