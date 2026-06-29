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
// (BrunoEbertContentView). A clone of BrunoRewatchablesView with two additions: the grid is ordered by
// Ebert rating (Thumbs Up highest-first, Thumbs Down lowest-first — `ascending`), and a "Browse by" genre
// pill row sub-filters the in-memory members by tagged TMDB genre (the same pattern as the Movies/genre
// surface — see docs/BRUNO_GENRE_PILLS_HOWTO.md).
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

    // MARK: Genre pill filter state (mirrors BrunoGenresView)

    /// COMMITTED filter; nil ⇒ "All". The grid follows this (debounced).
    @State
    private var selectedCore: BrunoCoreGenre?
    /// Transient focused highlight (cheap/instant) — the filter follows ~500 ms later.
    @State
    private var focusedCore: BrunoCoreGenre?
    /// Pending debounced write of focusedCore → selectedCore; each new focus cancels the prior.
    @State
    private var commitTask: Task<Void, Never>?
    /// INV-7: flipped true only after first paint, so the engine's initial pill assignment can't filter.
    @State
    private var filterRowAppeared = false
    /// Flips true once a pill is focused; arms defaultFocus (.userInitiated cold, .automatic after).
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
        .toolbar(.hidden, for: .navigationBar)
        .onFirstAppear {
            Task { await viewModel.load(parent: parent, ascending: ascending) }
        }
        .onDisappear {
            commitTask?.cancel()
            commitTask = nil
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

                        pillRow
                            .padding(.bottom, 30)

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

    // "Browse by" genre pills — sub-filter the in-memory members by tagged TMDB genre. Verbatim
    // choreography from BrunoGenresView.corePanel (no trailing "All Movies" / hero re-arm: the header
    // is non-focusable Text, so didEnterChipRow latches on first chip focus and .automatic thereafter).
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
            .backport
            .defaultFocus($focusedChip, "all", priority: didEnterChipRow ? .automatic : .userInitiated)
            .onChange(of: focusedChip) { _, newValue in
                if newValue != nil { didEnterChipRow = true }
            }
        }
        // INV-7: only after first paint, so the cold focus assignment can't fire a filter.
        .task { filterRowAppeared = true }
    }

    // Portrait posters, 7 across, each captioned with its Ebert star rating — laid out in a LazyVGrid so
    // they scroll inside the cinematic ScrollView beneath the hero band.
    private var grid: some View {
        LazyVGrid(columns: columns, spacing: EdgeInsets.edgePadding) {
            ForEach(shownFilms, id: \.id) { item in
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

    // MARK: Genre filtering

    // BROAD ONLY: each bucket maps to its broad TMDB genre(s) and nothing else (matches the Rewatchables
    // pills, owner's call). Keys MUST equal a BrunoCoreGenre.all id. Grid films carry raw TMDB `.genres`,
    // NOT the curated BoxSet names in BrunoCoreGenre.members — so this LOCAL map bridges bucket → TMDB
    // genre and matches item.genres (read-only; genre-layers hard rule). "international" is intentionally
    // omitted (no TMDB equivalent) so it auto-hides via shownCores.
    private static let tmdbGenresByCoreID: [String: Set<String>] = [
        "action-adventure": ["action", "adventure"],
        "comedy": ["comedy"],
        "drama": ["drama"],
        "romance": ["romance"],
        "scifi-fantasy": ["science fiction", "fantasy"],
        "thriller": ["thriller"],
        "crime": ["crime"],
        "horror": ["horror"],
        "history": ["history"],
        "family": ["family"],
    ]

    private func filmMatches(_ item: BaseItemDto, _ core: BrunoCoreGenre) -> Bool {
        guard let tmdb = Self.tmdbGenresByCoreID[core.id] else { return false }
        let genres = Set((item.genres ?? []).map { $0.lowercased() })
        return !genres.isDisjoint(with: tmdb)
    }

    /// The already-star-sorted members for "All", else only those whose TMDB genres fall in the selected
    /// bucket. In-memory ⇒ instant; the filter preserves the VM's star order.
    private var shownFilms: [BaseItemDto] {
        guard let selectedCore else { return viewModel.films }
        return viewModel.films.filter { filmMatches($0, selectedCore) }
    }

    /// Only buckets matching ≥1 loaded film — a pill can never filter to an empty grid (the G3 guard).
    private var shownCores: [BrunoCoreGenre] {
        BrunoCoreGenre.all.filter { core in viewModel.films.contains { filmMatches($0, core) } }
    }

    /// Record the focused core instantly (highlight) and DEBOUNCE the write to selectedCore (~500 ms),
    /// so scrubbing across the row never re-filters the grid mid-move. No-ops before first paint (INV-7).
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
