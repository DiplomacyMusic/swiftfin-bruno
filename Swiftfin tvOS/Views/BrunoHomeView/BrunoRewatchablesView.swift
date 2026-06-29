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
// each carrying its episode number in a `rewatchables-ep:NN` item tag) rendered as the cinematic
// item-detail shape — a tall RewatchablesHero hero band that scrolls away under a descending blur, with
// a dense portrait grid of every film beneath it. A LITERAL copy of BrunoStudiosGridView (itself a copy
// of the stock ItemView.CinematicScrollView — the "big hero band over a flat grid" the owner pointed at
// via the Directors detail page), swapping the landscape studio cards for portrait posters with the
// per-poster "Episode NN" caption (BrunoRewatchablesContentView). Members are fetched WITH .tags (the
// caption source); no genre bucketing — the whole collection is one grid.
struct BrunoRewatchablesView: View {

    let parent: BaseItemDto

    @StateObject
    private var viewModel = BrunoRewatchablesViewModel()

    @Router
    private var router

    // 7-up portrait, matching the stock library / Directors grid cell scale.
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
        // Draw our own cinematic title instead of the system nav title (mirrors BrunoStudiosGridView /
        // the other full-screen Bruno detail surfaces).
        .toolbar(.hidden, for: .navigationBar)
        .onFirstAppear {
            Task { await viewModel.load(parent: parent) }
        }
    }

    private var content: some View {
        GeometryReader { proxy in
            ZStack {
                // Full-bleed brand backdrop (the podcast art) — fills the whole screen, edge to edge,
                // mirroring the detail page's ImageView layer. Image(_:) loads the asset-catalog still.
                Image("RewatchablesHero")
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
                    // The SAME BlurView(.dark) + descending gradient-mask as the detail page / Studios:
                    // as the grid scrolls up, the hero blurs and its colors descend behind the posters.
                    // (Deliberately a scroll-coupled `.background` blur — the INV-6 carve-out Studios
                    // already takes — because that descending blur IS the cinematic effect being matched.)
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

    // The "Rewatchables" title, bottom-left over the backdrop — the place the detail page puts the
    // title/logo.
    private var header: some View {
        VStack(alignment: .leading) {
            Spacer()
            Text("Rewatchables")
                .font(.brunoDisplay(72, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 50)
    }

    // Portrait posters, 7 across, each captioned with its "Episode NN" — laid out in a LazyVGrid so they
    // scroll inside the cinematic ScrollView beneath the hero band.
    private var grid: some View {
        LazyVGrid(columns: columns, spacing: EdgeInsets.edgePadding) {
            ForEach(viewModel.films, id: \.id) { item in
                PosterButton(item: item, type: .portrait) {
                    router.route(to: .item(item: item))
                } label: {
                    BrunoRewatchablesContentView(item: item)
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
