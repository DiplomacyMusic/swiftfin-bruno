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
// The Ebert drill-in: the "Ebert Thumbs Up" + "Ebert Thumbs Down" curated BoxSets rendered as ONE
// cinematic surface — a tall hero band (the Roger Ebert photo) over a portrait grid of every film,
// each captioned with its star rating (BrunoEbertContentView). A flip toggle above the genre pills
// switches between the two verdicts: pressing it swaps the thumb icon, the toggle label, the hero
// title, the film set, the star-sort direction (Up highest-first / Down lowest-first), and the pills —
// all in-memory (both sets load on appear), so the switch is instant. A clone of BrunoRewatchablesView's
// hero+grid shape; the "Browse by" pills mirror the Movies/genre surface (docs/BRUNO_GENRE_PILLS_HOWTO.md).
//
// `down == nil` ⇒ a single-set entry (e.g. a lone Ebert shelf surfaced on Home): no toggle, sort taken
// from `up`'s own name.
struct BrunoEbertView: View {

    let up: BaseItemDto
    let down: BaseItemDto?
    /// Which verdict to open on (set by the route — a "Thumbs Down" shelf opens on Down). Applied once
    /// on first appear; only meaningful when `down != nil`.
    var initialShowingDown: Bool = false

    @StateObject
    private var viewModel = BrunoEbertViewModel()

    @Router
    private var router

    // 7-up portrait, matching the stock library / Rewatchables grid cell scale.
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: EdgeInsets.edgePadding),
        count: 7
    )

    /// Which verdict is shown. Only meaningful when `down != nil`.
    @State
    private var showingDown = false

    // MARK: Genre pill filter state (mirrors BrunoGenresView)

    @State
    private var selectedCore: BrunoCoreGenre?
    @State
    private var focusedCore: BrunoCoreGenre?
    @State
    private var commitTask: Task<Void, Never>?
    /// INV-7: flipped true only after first paint, so the engine's initial pill assignment can't filter.
    @State
    private var filterRowAppeared = false
    @State
    private var didEnterChipRow = false

    @FocusState
    private var focusedChip: String?
    @FocusState
    private var toggleFocused: Bool

    /// The film set currently shown (already star-sorted by the VM). The pill filter operates on this.
    private var films: [BaseItemDto] {
        showingDown ? viewModel.downFilms : viewModel.upFilms
    }

    /// Hero + toggle title for the shown verdict.
    private var displayedTitle: String {
        showingDown ? (down?.displayTitle ?? up.displayTitle) : up.displayTitle
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(2)
                    .tint(Color.bruno.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if films.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onFirstAppear {
            showingDown = down != nil && initialShowingDown
            Task { await viewModel.load(up: up, down: down) }
        }
        .onDisappear {
            commitTask?.cancel()
            commitTask = nil
        }
    }

    private var content: some View {
        GeometryReader { proxy in
            ZStack {
                // Full-bleed brand backdrop: swaps immediately with the verdict toggle — the thumbs-up
                // photo for the Up set, thumbs-down for Down (owner request). `down == nil` (a lone
                // single-set entry, no toggle) always shows the Up photo.
                Image(showingDown ? "RogerHeroThumbsDown" : "RogerHeroThumbsUp")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                            .frame(height: proxy.size.height - 150)
                            .padding(.bottom, 50)

                        // The Up ⇄ Down switch, above the pills — only when both verdicts are present.
                        if down != nil {
                            verdictToggle
                                .padding(.bottom, 24)
                        }

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

    // The shelf title, bottom-left over the backdrop — swaps with the toggle ("Ebert Thumbs Up"/"Down").
    private var header: some View {
        VStack(alignment: .leading) {
            Spacer()
            Text(displayedTitle)
                .font(.brunoDisplay(72, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 50)
    }

    // The flip switch: a big thumb icon + label. Pressing flips the verdict — and with it the icon,
    // label, hero title, film set, sort, and pills. The accent focus ring is ALWAYS present and
    // opacity-toggled (never an `if`-inserted view) and the icon swaps via content, so the focused
    // subtree stays structurally constant (INV-10). Styled like BrunoSelectorCard's pills.
    private var verdictToggle: some View {
        Button(action: flipVerdict) {
            HStack(spacing: 22) {
                Image(systemName: showingDown ? "hand.thumbsdown.fill" : "hand.thumbsup.fill")
                    .font(.system(size: 40, weight: .semibold))
                Text(showingDown ? "Thumbs Down" : "Thumbs Up")
                    .font(.brunoBody(28, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.bruno.accent)
            .padding(.horizontal, 40)
            .padding(.vertical, 18)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.bruno.fg.opacity(toggleFocused ? 0.22 : 0.12))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.bruno.accent, lineWidth: 3)
                    .opacity(toggleFocused ? 1 : 0)
            }
            .scaleEffect(toggleFocused ? 1.05 : 1.0)
            .animation(.easeOut(duration: 0.15), value: toggleFocused)
        }
        .buttonStyle(BrunoChromelessButtonStyle())
        .focused($toggleFocused)
        // Its own focus region (sibling above the pills) so UP/DOWN escape to hero / pills correctly.
        .focusSection()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 50)
    }

    private func flipVerdict() {
        showingDown.toggle()
        // The new set has a different genre mix; reset the filter to "All".
        selectedCore = nil
        focusedCore = nil
        commitTask?.cancel()
    }

    // "Browse by" genre pills — sub-filter the in-memory members by tagged TMDB genre. Verbatim
    // choreography from BrunoGenresView.corePanel.
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

    /// The shown set for "All", else only films whose TMDB genres fall in the selected bucket. In-memory
    /// ⇒ instant; the filter preserves the VM's star order.
    private var shownFilms: [BaseItemDto] {
        guard let selectedCore else { return films }
        return films.filter { filmMatches($0, selectedCore) }
    }

    /// Only buckets matching ≥1 film in the shown set — a pill can never filter to an empty grid.
    private var shownCores: [BrunoCoreGenre] {
        BrunoCoreGenre.all.filter { core in films.contains { filmMatches($0, core) } }
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

// MARK: - BrunoChromelessButtonStyle

// Suppresses the system's default tvOS button highlight so the toggle's OWN accent ring is the focus
// cursor (mirrors BrunoSelectorCard's private BrunoSelectorButtonStyle).
private struct BrunoChromelessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - BrunoEbertViewModel

@MainActor
final class BrunoEbertViewModel: ViewModel {

    @Published
    private(set) var upFilms: [BaseItemDto] = []
    @Published
    private(set) var downFilms: [BaseItemDto] = []
    @Published
    private(set) var isLoading = true

    func load(up: BaseItemDto, down: BaseItemDto?) async {
        guard let userSession, let upID = up.id else {
            isLoading = false
            return
        }
        let client = userSession.client
        let userID = userSession.user.id

        // The "up" set is highest-first; a lone single-set entry instead sorts by its OWN name (so a
        // standalone "Thumbs Down" shelf still reads lowest-first).
        let upAscending = down == nil && up.displayTitle.lowercased().contains("down")
        let upMembers = await Self.fetchMembers(client: client, userID: userID, parentID: upID)
        upFilms = BrunoEbert.ordered(upMembers, ascending: upAscending)

        if let down, let downID = down.id {
            let downMembers = await Self.fetchMembers(client: client, userID: userID, parentID: downID)
            downFilms = BrunoEbert.ordered(downMembers, ascending: true) // Thumbs Down: lowest-first
        }
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

    /// The merged Ebert grid. `down == nil` ⇒ single-set (no toggle).
    @MainActor
    static func brunoEbert(up: BaseItemDto, down: BaseItemDto?, showingDown: Bool = false) -> NavigationRoute {
        NavigationRoute(
            id: "bruno-ebert-\(up.id ?? up.displayTitle)"
        ) {
            BrunoEbertView(up: up, down: down, initialShowingDown: showingDown)
        }
    }
}
