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

// MARK: - BrunoCoreGenre

//
// A curated "core" genre bucket shown as the first line of the Genres page. Each maps to several
// fine-grain server genres by keyword, so it works without hardcoding the server's exact genre
// names. Selecting one opens a page of only that bucket's fine-grain genre shelves.
struct BrunoCoreGenre: Identifiable, Hashable {

    let id: String
    let title: String
    let keywords: [String]

    /// Does a fine-grain server genre (e.g. "Science Fiction", "Adventure") belong to this bucket?
    func matches(_ genreName: String) -> Bool {
        let lowered = genreName.lowercased()
        return keywords.contains { lowered.contains($0) }
    }

    static let all: [BrunoCoreGenre] = [
        .init(id: "action", title: "Action", keywords: ["action", "adventure", "martial", "war", "western", "spy", "superhero"]),
        .init(
            id: "scifi-fantasy",
            title: "Sci-Fi & Fantasy",
            keywords: ["sci-fi", "scifi", "science fiction", "fantasy", "supernatural"]
        ),
        // "romcom"/"rom-com" so the curated "RomCom All-Timers" shelf lands in this bucket
        // (its name contains neither "romance" nor "romantic").
        .init(id: "romance", title: "Romance", keywords: ["romance", "romantic", "romcom", "rom-com"]),
        .init(id: "comedy", title: "Comedy", keywords: ["comedy", "comedies", "sitcom", "stand-up"]),
        .init(id: "drama", title: "Drama", keywords: ["drama"]),
    ]
}

// MARK: - BrunoGenresView (tvOS only)

//
// The Genres page (roadmap §4 + core panel). With `core == nil`: a core-category panel as the
// first line (Action · Sci-Fi & Fantasy · Romance · Comedy · Drama), then the mixed-together
// sub-genre shelves. With a `core` set: only the fine-grain genre shelves in that bucket.
struct BrunoGenresView: View {

    let parent: BaseItemDto
    let core: BrunoCoreGenre?

    /// True when this view is the Movies tab ROOT (not a pushed cover): suppress the self-applied
    /// menu bar (MainTabView already supplies one to tab roots; re-pinning would double-bar — the
    /// e44e1e71 regression). Default false keeps the existing `.brunoGenres` cover bar.
    let isTabRoot: Bool
    /// When non-nil, the core panel appends a trailing "All Movies" pill running this action (pushes
    /// the lazy A–Z grid). Pure navigation — it never commits a genre filter.
    let onShowAll: (() -> Void)?

    @StateObject
    private var viewModel = BrunoBoxSetShelvesViewModel()

    /// The COMMITTED core-genre filter — the one `shownCategories` actually filters on. Changed IN
    /// PLACE (no navigation push, no refetch) so switching genres is instant — the full set is already
    /// loaded in `viewModel`. Driven by the debounced commit ~500 ms after focus settles, so a fast
    /// left-right scrub across the pill row rebuilds the shelf stack exactly ONCE, not per pill.
    @State
    private var selectedCore: BrunoCoreGenre?

    /// The FOCUSED core (transient, set instantly as the focus ring passes each pill). Drives the pill
    /// highlight (cheap) so highlighting feels instant while the shelves settle via `selectedCore`.
    /// `nil` ⇒ the "All" chip. A non-toggling target: the focused pill, never cleared by re-focusing.
    @State
    private var focusedCore: BrunoCoreGenre?

    /// The pending debounced write of `focusedCore → selectedCore`. Stored so each new focus cancels
    /// the previous pending commit (coalescing a scrub into one rebuild) and `onDisappear` can cancel it.
    @State
    private var commitTask: Task<Void, Never>?

    /// INV-7 guard: true only AFTER the first paint, so the focus engine's initial focus assignment
    /// to the pill row can't fire a filter on cold enter. Until this flips, a focus-driven commit no-ops.
    @State
    private var filterRowAppeared = false

    /// The hero's featured item, computed ONCE from the FULL unfiltered set and held fixed. A pill
    /// change must never reload the 720pt hero backdrop, so this is decoupled from `shownCategories`.
    @State
    private var featuredItem: BaseItemDto?

    /// Which pill currently holds focus ("all" or a core id). Drives `defaultFocus` so entering the row
    /// from the hero (DOWN) lands on the leftmost "All" pill, not whatever was last focused/selected —
    /// the focus engine otherwise restores the previously-focused (middle) pill.
    @FocusState
    private var focusedChip: String?

    /// Flips true once the pill row has been focused. Before: `defaultFocus` forces "All" (.userInitiated);
    /// after: it yields to restoration (.automatic) so UP-from-shelves returns to the active genre.
    @State
    private var didEnterChipRow = false

    init(parent: BaseItemDto, core: BrunoCoreGenre?, isTabRoot: Bool = false, onShowAll: (() -> Void)? = nil) {
        self.parent = parent
        self.core = core
        self.isTabRoot = isTabRoot
        self.onShowAll = onShowAll
        _selectedCore = State(initialValue: core)
        _focusedCore = State(initialValue: core)
    }

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
                // No sub-genre card row: the core panel is the only chrome up top; each shelf's
                // "Show all" reaches the full grid. Selecting a core re-filters `shownCategories`
                // from the already-loaded set — instant, no spinner.
                BrunoCategoryShelves(
                    categories: shownCategories,
                    eyebrow: "If You Like",
                    header: AnyView(corePanel),
                    showCategoryRow: false,
                    // Name each shelf's "Show all" card with its genre ("Show all · Time Travel").
                    namesShowAllCards: true,
                    // INV-7 / decoupled hero: the FIXED item from the full set, never re-derived per
                    // pill, so a filter change can't reload the hero backdrop (heroEyebrow may still vary).
                    featured: featuredItem,
                    heroEyebrow: selectedCore.map { "\($0.title) Pick" } ?? "Featured Film",
                    // Snap the pills to the top when the row gains focus (instant) so the genre shelves
                    // are fully visible beneath and you watch them change. Stable token (not the pill id)
                    // to avoid re-evaluating the shelf view per scrub.
                    pillScrollKey: focusedChip == nil ? nil : "pills"
                )
                // As a pushed cover this occludes MainTabView's tab bar — re-pin the Bruno top menu bar
                // here. Attached at the COVER call site (not inside BrunoCategoryShelves). As the Movies
                // TAB ROOT (isTabRoot) MainTabView already supplies the bar, so suppress it to avoid a
                // double bar — same precedent as the Collections tab root.
                .if(!isTabRoot) { $0.brunoHeroMenuBar() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onFirstAppear {
            Task { await viewModel.load(parent: parent) }
        }
        // Compute the hero ONCE from the FULL unfiltered set when categories land (and never per pill).
        .onChange(of: viewModel.categories.map(\.id)) { _, _ in
            featuredItem = brunoFeaturedItem(in: viewModel.categories)
        }
        .onDisappear {
            commitTask?.cancel()
            commitTask = nil
        }
    }

    /// All fine-grain genres when nothing is selected; only the bucket's genres when a core is active.
    private var shownCategories: [BrunoCollectionCategory] {
        guard let selectedCore else { return viewModel.categories }
        return viewModel.categories.filter { selectedCore.matches($0.name) }
    }

    /// Only the core buckets that actually match ≥1 loaded sub-genre — so a pill can never commit to an
    /// EMPTY shelf set (which would leave the hero + pills over a blank shelf area). `viewModel.categories`
    /// is fixed for the session, so this is stable (no pills appearing/vanishing mid-use).
    private var shownCoreGenres: [BrunoCoreGenre] {
        BrunoCoreGenre.all.filter { core in viewModel.categories.contains { core.matches($0.name) } }
    }

    private var corePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by".uppercased())
                .font(.brunoBody(20, weight: .semibold))
                .tracking(3)
                .foregroundStyle(Color.bruno.accent)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    // "All" chip: a first-class in-HStack pill (matches Kids' uniformity) and the only
                    // path back to the unfiltered set. Highlighted off the FOCUSED value (instant).
                    BrunoSelectorCard(
                        title: "All",
                        isSelected: focusedCore == nil,
                        selectsOnFocus: true
                    ) {
                        commitFocus(nil)
                    }
                    .focused($focusedChip, equals: "all")

                    ForEach(shownCoreGenres) { coreGenre in
                        BrunoSelectorCard(
                            // Highlight off FOCUSED (cheap/instant); the filter follows ~500 ms later.
                            title: coreGenre.title,
                            isSelected: focusedCore?.id == coreGenre.id,
                            // Move-to-select: landing the ring on a pill focuses it; the shelves settle
                            // once via the debounced commit (non-toggling — "All" is the only clear path).
                            selectsOnFocus: true
                        ) {
                            commitFocus(coreGenre)
                        }
                        .focused($focusedChip, equals: coreGenre.id)
                    }

                    // Trailing escape hatch to the full A–Z grid (Movies tab only). PURE navigation:
                    // selectsOnFocus:false so scrubbing across it doesn't push; it never commits a genre
                    // (no commitFocus, isSelected always false), so the genre filter is untouched.
                    if let onShowAll {
                        BrunoSelectorCard(
                            title: "All Movies",
                            isSelected: false,
                            selectsOnFocus: false
                        ) {
                            onShowAll()
                        }
                        .focused($focusedChip, equals: "show-all")
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 8)
            }
            .focusSection()
            // First entry into the row (cold DOWN-from-hero) lands on "All" (.userInitiated outranks the
            // engine's last-focused restoration); after that .automatic yields to restoration so UP from
            // the shelves returns to the active genre rather than resetting to All.
            .backport
            .defaultFocus($focusedChip, "all", priority: didEnterChipRow ? .automatic : .userInitiated)
            .onChange(of: focusedChip) { _, newValue in
                if newValue != nil { didEnterChipRow = true }
            }
        }
        // INV-7: flip the appeared guard only after the first paint, so the focus engine's initial
        // assignment to the pill row can't fire a commit on cold enter (hero shows the unfiltered set).
        .task { filterRowAppeared = true }
    }

    /// Record the focused core instantly (drives the highlight) and DEBOUNCE the write to the
    /// committed `selectedCore` (~500 ms after focus settles), so scrubbing across the row never rebuilds
    /// the shelf stack mid-move — only a deliberate PAUSE on a genre commits. No-ops before first paint
    /// (INV-7) and when nothing changed.
    private func commitFocus(_ core: BrunoCoreGenre?) {
        guard filterRowAppeared else { return }
        guard focusedCore?.id != core?.id || selectedCore?.id != core?.id else { return }

        focusedCore = core
        commitTask?.cancel()
        commitTask = Task {
            // 500 ms: scrubbing across genres doesn't rebuild shelves until the user settles.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            // Commit only if focus still rests on the same pill (no-op if already committed there).
            guard focusedCore?.id == core?.id, selectedCore?.id != core?.id else { return }
            selectedCore = core
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No genres yet")
                .font(.brunoDisplay(40, weight: .semibold))
                .foregroundStyle(Color.bruno.fg)
            Text("Genres from this server will appear here.")
                .font(.brunoBody(22))
                .foregroundStyle(Color.bruno.fgMuted)

            // Tab-root escape hatch: if the Genres group resolves but its shelves don't load (server
            // hiccup / no children), never strand the Movies tab on a dead end with no path to any film —
            // offer the full A–Z library (same target as the "All Movies" pill). Cover entry has no
            // onShowAll, so this only shows at the tab root.
            if let onShowAll {
                BrunoSelectorCard(title: "All Movies", isSelected: false, selectsOnFocus: false) {
                    onShowAll()
                }
                .padding(.top, 24)
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - NavigationRoute

extension NavigationRoute {

    @MainActor
    static func brunoGenres(parent: BaseItemDto, core: BrunoCoreGenre?) -> NavigationRoute {
        NavigationRoute(
            id: "bruno-genres-\(parent.id ?? parent.displayTitle)-\(core?.id ?? "all")"
        ) {
            BrunoGenresView(parent: parent, core: core)
        }
    }
}
