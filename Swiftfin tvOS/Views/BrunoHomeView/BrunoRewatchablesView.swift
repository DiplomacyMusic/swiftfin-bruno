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
// caption source) and .genres (the pill filter source); a "Browse by" pill row above the grid sub-filters
// the films by their tagged genre, reusing the Movies-tab BrunoCoreGenre buckets (see BrunoGenresView).
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

    // MARK: Genre pill filter

    //
    // Ported from the Movies-tab "Browse by" pills (BrunoGenresView). The committed `selectedCore` filters
    // the in-memory `films` to `shownFilms`; `focusedCore` drives the instant highlight while the debounced
    // `commitFocus` settles the grid once after a scrub. INV-7: `filterRowAppeared` blocks a filter on the
    // focus engine's initial pill assignment, so cold enter shows the full set.

    @State
    private var selectedCore: BrunoCoreGenre?
    @State
    private var focusedCore: BrunoCoreGenre?
    @State
    private var commitTask: Task<Void, Never>?
    @State
    private var filterRowAppeared = false
    @State
    private var didEnterChipRow = false

    @FocusState
    private var focusedChip: String?

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
        .onDisappear {
            commitTask?.cancel()
            commitTask = nil
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

                        pillRow
                            .padding(.bottom, 30)

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
            ForEach(shownFilms, id: \.id) { item in
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

    // MARK: - Genre pill filter

    // The pills reuse the Movies-tab BrunoCoreGenre buckets, but those buckets' `members` are curated
    // sub-genre BoxSet NAMES — the Rewatchables films instead carry raw TMDB `.genres` strings. So map each
    // bucket to the TMDB genres that belong under it and match the film's `.genres` (read-only — the
    // genre-layers hard rule). "International" has no TMDB-genre equivalent, so it matches no film and is
    // auto-hidden by `shownCores`.
    private static let tmdbGenresByCoreID: [String: Set<String>] = [
        "action-adventure": ["action", "adventure", "western"],
        "comedy": ["comedy"],
        "drama": ["drama", "music"],
        "romance": ["romance"],
        "scifi-fantasy": ["science fiction", "fantasy"],
        "thriller": ["thriller", "mystery"],
        "crime": ["crime"],
        "horror": ["horror"],
        "history": ["history", "war"],
        "family": ["family", "animation"],
    ]

    private func filmMatches(_ item: BaseItemDto, _ core: BrunoCoreGenre) -> Bool {
        guard let tmdb = Self.tmdbGenresByCoreID[core.id] else { return false }
        let genres = Set((item.genres ?? []).map { $0.lowercased() })
        return !genres.isDisjoint(with: tmdb)
    }

    /// The full set for "All", else only the films whose TMDB genres fall in the selected bucket. An
    /// in-memory filter (every member is already loaded), so switching pills is instant — no refetch.
    private var shownFilms: [BaseItemDto] {
        guard let selectedCore else { return viewModel.films }
        return viewModel.films.filter { filmMatches($0, selectedCore) }
    }

    /// Only the buckets matching ≥1 loaded film — so a pill can never filter to an empty grid (mirrors the
    /// Movies-tab `shownCoreGenres` G3 guard). Auto-hides International + any genre absent from the set.
    private var shownCores: [BrunoCoreGenre] {
        BrunoCoreGenre.all.filter { core in viewModel.films.contains { filmMatches($0, core) } }
    }

    // The "Browse by" pill row above the grid — same component + focus choreography as BrunoGenresView's
    // core panel. Move-to-select with a debounced commit; its own `.focusSection()` so UP/DOWN traverse
    // cleanly between the pills and the grid.
    private var pillRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by".uppercased())
                .font(.brunoBody(20, weight: .semibold))
                .tracking(3)
                .foregroundStyle(Color.bruno.accent)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    BrunoSelectorCard(
                        title: "All",
                        isSelected: focusedCore == nil,
                        selectsOnFocus: true
                    ) {
                        commitFocus(nil)
                    }
                    .focused($focusedChip, equals: "all")

                    ForEach(shownCores) { core in
                        BrunoSelectorCard(
                            title: core.title,
                            isSelected: focusedCore?.id == core.id,
                            selectsOnFocus: true
                        ) {
                            commitFocus(core)
                        }
                        .focused($focusedChip, equals: core.id)
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 8)
            }
            .focusSection()
            // First entry (cold DOWN into the row) lands on "All" (.userInitiated outranks restoration);
            // after that .automatic yields so UP-from-grid returns to the active genre.
            .backport
            .defaultFocus($focusedChip, "all", priority: didEnterChipRow ? .automatic : .userInitiated)
            .onChange(of: focusedChip) { _, newValue in
                if newValue != nil { didEnterChipRow = true }
            }
        }
        // INV-7: flip the guard only after first paint, so the engine's initial pill assignment can't
        // commit a filter on cold enter (the grid shows the full set until the user picks a pill).
        .task { filterRowAppeared = true }
    }

    /// Record the focused bucket instantly (highlight) and DEBOUNCE the commit to `selectedCore` (~500 ms
    /// after focus settles) so scrubbing across the row re-filters the grid once, not per pill. No-ops
    /// before first paint (INV-7) and when nothing changed.
    private func commitFocus(_ core: BrunoCoreGenre?) {
        guard filterRowAppeared else { return }
        guard focusedCore?.id != core?.id || selectedCore?.id != core?.id else { return }

        focusedCore = core
        commitTask?.cancel()
        commitTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard focusedCore?.id == core?.id, selectedCore?.id != core?.id else { return }
            selectedCore = core
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
        // .tags carries rewatchables-ep:NN for the per-poster "Episode NN" caption; .genres feeds the
        // "Browse by" pill filter (each film's raw TMDB genres). 300 > 214 so the whole set is one page.
        parameters.fields = .MinimumFields + [.tags, .genres]
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
