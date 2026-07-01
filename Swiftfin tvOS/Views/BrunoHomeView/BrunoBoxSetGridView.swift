//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionVGrid
import JellyfinAPI
import SwiftUI

// Prototype copy is English-only; localization (L10n) is a deferred TODO (see BRUNO_NOTES.md).
// swiftlint:disable hard_coded_display_string

// MARK: - BrunoBoxSetGridView (tvOS only)

//
// "Show all" grid for a flat, already-fetched list of box sets (Boxed Sets in landscape;
// Directors / Studios sub-collections in portrait). A dedicated wrapper over CollectionVGrid — the
// same recycling grid the stock PagingLibraryView uses internally — rather than PagingLibraryView
// itself, because:
//  1. PagingLibraryView's poster style is a user-GLOBAL default; we can't request landscape for
//     just this route without leaking the change to every library.
//  2. We own the cell label (the collection name / "Collection" / film-count + year-range lockup).
//  3. We own the top inset, so the grid sits BELOW the nav title instead of scrolling under it.
struct BrunoBoxSetGridView: View {

    let title: String
    let items: [BaseItemDto]
    let posterType: PosterDisplayType
    /// Boxed Sets only: the "{Title} Collection" / film-count / year-range lockup (+ the year fetch).
    /// Off for Studios/Directors, which are plain name tiles.
    var collectionLabel: Bool = false
    /// Directors: focus-driven card that cycles the director's film posters (BrunoArtCarouselCard).
    /// Off for Boxed Sets, which keep the plain PosterButton.
    var artCarousel: Bool = false
    /// New Releases "Show all": render each poster's full release date on line 2 (the deeper New
    /// Releases collection, matching the Home/Collections inline rows). Portrait, non-collectionLabel.
    var showsDate: Bool = false
    /// Oscar "Show all": render each poster's "Winner (Year)" / "Nominee (Year)" line for this
    /// category (BrunoOscarContentView). Paired with `oscarParent` so the grid pages the FULL category
    /// (the drill-in only hands us a small preview) and sorts it reverse-chronologically.
    var oscarCategory: BrunoOscarCategory?
    /// The real Oscar BoxSet to page the complete, reverse-chron film set from. Set only for Oscar
    /// "Show all"; nil ⇒ the grid renders the static `items` as before.
    var oscarParent: BaseItemDto?
    /// §7 cinematic hero: an asset-catalog still drawn full-bleed behind a tall title header above the
    /// grid (the Studios look, via BrunoBrandHeroBand). nil ⇒ the plain CollectionVGrid layout (the
    /// default for New Releases / Oscar grids, which keep recycling). Set for Directors / Movie Stars /
    /// Box Sets — a stand-in is each category's existing card art, easy to swap for bespoke art later.
    var heroAsset: String?
    /// §5 Household Names: a recognizable-name shortlist (e.g. marquee directors). When non-empty AND a
    /// hero is shown, the names present in `items` surface in a pinned "Household Names" section above
    /// the full A–Z grid (Studios pattern). nil/empty ⇒ no shortlist section.
    var householdNames: [String]?
    /// The label over the full grid when a Household Names section is shown (e.g. "All Directors").
    var allSectionTitle: String = "All"
    /// Seasonal "Show all" only: a bundled static asset-catalog image standing in for a sub-collection's
    /// own server poster (owner request, 2026-06-30 — mirrors the same override on the Collections
    /// inline shelf, BrunoShelfRow.assetOverride, so the drill-down and the preview show the same themed
    /// cover). nil (default, or nil per-item) ⇒ the standard artCarousel/PosterButton cell.
    var assetOverride: ((BaseItemDto) -> String?)?

    @Router
    private var router

    /// Per-collection release-year ranges (Boxed Sets only), fetched lazily on appear.
    @StateObject
    private var yearRanges = BrunoBoxSetYearRangesViewModel()

    /// Oscar "Show all" only: the complete, reverse-chron category fetched on appear. nil until loaded,
    /// when it replaces the preview `items` (one grid rebuild — see `gridIdentity`).
    @StateObject
    private var oscarFull = BrunoOscarGridViewModel()

    /// The full reverse-chron Oscar set once paged, else the passed-in (preview / static) items.
    private var gridItems: [BaseItemDto] {
        oscarFull.items ?? items
    }

    var body: some View {
        Group {
            if let heroAsset {
                // §7: cinematic hero path (loses CollectionVGrid recycling — owner-blessed for these
                // bounded Collections drill-ins). Owns its own nav-bar suppression via BrunoBrandHeroBand.
                cinematicLayout(heroAsset: heroAsset)
            } else {
                // Default path — New Releases / Oscar grids keep the recycling CollectionVGrid untouched.
                grid
                    .navigationTitle(title)
            }
        }
        .onFirstAppear {
            if collectionLabel { yearRanges.load(items: items) }
            if let oscarParent, let oscarCategory {
                oscarFull.load(parent: oscarParent, category: oscarCategory)
            }
        }
    }

    private var grid: some View {
        CollectionVGrid(
            uniqueElements: gridItems,
            layout: layout
        ) { item in
            cell(for: item)
        }
        // CollectionVGrid is UIKit-backed and won't re-render cells when async data arrives; rebuild
        // the grid ONCE when a fetch completes (the @StateObject VMs persist, so this doesn't refetch).
        // `yearRanges.done` flips false→true a single time (Boxed Sets); the Oscar paging flips
        // `oscarFull.items` nil→non-nil a single time. Each is at most one rebuild.
        .id(gridIdentity)
        .scrollIndicators(.hidden)
    }

    // §5/§7: the cinematic ScrollView + LazyVGrid path. Mirrors BrunoStudiosGridView line-for-line
    // (full-bleed backdrop, tall title header, optional "Household Names" shortlist above the full
    // A–Z grid, descending blur), reusing the shared BrunoBrandHeroBand so there's one band, not one
    // per grid. The shortlist + grid `ForEach` key on `\.id` (INV-2) and the shortlist membership is a
    // pure function of the already-fetched `items`, so it's present from first frame (no async flip
    // that would restructure a focused container — INV-10).
    private func cinematicLayout(heroAsset: String) -> some View {
        BrunoBrandHeroBand(title: title, backdropAsset: heroAsset) {
            let top = topNames
            if top.isNotEmpty {
                BrunoBrandHeroSectionTitle("Household Names")
                lazyGrid(for: top)
                BrunoBrandHeroSectionTitle(allSectionTitle)
            }
            lazyGrid(for: gridItems)
        }
        .id(gridIdentity)
    }

    private func lazyGrid(for list: [BaseItemDto]) -> some View {
        LazyVGrid(columns: lazyColumns, spacing: EdgeInsets.edgePadding) {
            ForEach(list, id: \.id) { item in
                cell(for: item)
            }
        }
        .padding(.horizontal, EdgeInsets.edgePadding)
        .padding(.bottom, 50)
    }

    private var lazyColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: EdgeInsets.edgePadding),
            count: posterType == .landscape ? 4 : 7
        )
    }

    // The card cell — shared by the CollectionVGrid (default) and LazyVGrid (cinematic) layouts so the
    // two paths render identical tiles.
    @ViewBuilder
    private func cell(for item: BaseItemDto) -> some View {
        if let asset = assetOverride?(item) {
            // Seasonal: bundled themed cover instead of the sub-collection's own server poster or
            // cycling film art — same scaledToFill treatment as the Collections inline shelf override.
            Button {
                router.route(to: .item(item: item))
            } label: {
                ZStack {
                    Color.black
                    Image(asset)
                        .resizable()
                        .scaledToFill()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .posterStyle(posterType)

                cardLabel(for: item)
            }
            .buttonStyle(.card)
        } else if artCarousel {
            BrunoArtCarouselCard(item: item, type: posterType) {
                router.route(to: .item(item: item))
            } label: {
                cardLabel(for: item)
            }
        } else {
            PosterButton(item: item, type: posterType) {
                router.route(to: .item(item: item))
            } label: {
                cardLabel(for: item)
            }
        }
    }

    // MARK: Household Names (curated + daily-seeded rotation) — §5

    // The most recognizable directors, in rough editorial order — the Directors-grid analogue of
    // BrunoStudiosGridView.recognizableStudios. Only names actually present as director collections in
    // `items` surface (over-listing is safe — absent names are dropped), capped at two portrait rows
    // and day-rotated. Includes the owner's hard-adds: Damien Chazelle, Cameron Crowe, Robert Eggers.
    static let recognizableDirectors: [String] = [
        "Steven Spielberg",
        "Martin Scorsese",
        "Alfred Hitchcock",
        "Stanley Kubrick",
        "Christopher Nolan",
        "Quentin Tarantino",
        "Francis Ford Coppola",
        "Akira Kurosawa",
        "Ridley Scott",
        "David Fincher",
        "Paul Thomas Anderson",
        "Wes Anderson",
        "Spike Lee",
        "Coen Brothers",
        "Joel Coen",
        "Ethan Coen",
        "James Cameron",
        "Denis Villeneuve",
        "David Lynch",
        "Tim Burton",
        "Clint Eastwood",
        "Robert Zemeckis",
        "Ron Howard",
        "Peter Jackson",
        "Guillermo del Toro",
        "Sofia Coppola",
        "Greta Gerwig",
        "Damien Chazelle",
        "Cameron Crowe",
        "Robert Eggers",
        "John Hughes",
    ]

    // Stable membership (the recognizable names present in `items`, capped at two full rows), order
    // rotated by a day-stamp seed so it feels fresh daily without dropping a name. Mirrors
    // BrunoStudiosGridView.topStudios. Empty when no `householdNames` list was supplied.
    private var topNames: [BaseItemDto] {
        guard let householdNames, householdNames.isNotEmpty else { return [] }
        var byName: [String: BaseItemDto] = [:]
        for item in items {
            guard let name = item.name else { continue }
            let key = Self.normalizeName(name)
            if byName[key] == nil { byName[key] = item }
        }
        let limit = (posterType == .landscape ? 4 : 7) * 2 // two full rows
        let membership = householdNames
            .compactMap { byName[Self.normalizeName($0)] }
            .prefix(limit)
        return BrunoRNG.shuffled(Array(membership), seed: daySeed)
    }

    // Lowercase + alphanumerics only, so "Cameron Crowe" matches "cameroncrowe" regardless of
    // punctuation/spacing (mirrors BrunoStudiosGridView.normalizeStudio).
    private static func normalizeName(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // Day-stamp seed (year*10000 + month*100 + day): stable within a calendar day, rotates each new
    // day — the same per-day rotation Studios + the Home spotlight use.
    private var daySeed: UInt32 {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return UInt32(truncatingIfNeeded: (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0))
    }

    /// Single token driving the at-most-two one-shot grid rebuilds (year-range fetch, Oscar paging).
    private var gridIdentity: String {
        "\(yearRanges.done)-\(oscarFull.items != nil)"
    }

    // Mirrors the stock tvOS landscape/portrait grid layout (LibraryElement.layout): 4 columns
    // landscape, 7 portrait, edge-padding insets/spacing.
    private var layout: CollectionVGridLayout {
        let columns = posterType == .landscape ? 4 : 7
        return .columns(
            columns,
            insets: .init(vertical: 0, horizontal: EdgeInsets.edgePadding),
            itemSpacing: EdgeInsets.edgePadding,
            lineSpacing: EdgeInsets.edgePadding
        )
    }

    @ViewBuilder
    private func cardLabel(for item: BaseItemDto) -> some View {
        if posterType == .landscape, collectionLabel {
            BrunoBoxSetCardLabel(item: item, yearRange: yearRanges.ranges[item.id ?? ""])
        } else if let oscarCategory {
            // Oscar "Show all": "Winner (Year)" / "Nominee (Year)" on line 2 for this category.
            BrunoOscarContentView(item: item, category: oscarCategory)
        } else if showsDate {
            // New Releases "Show all": full release date on line 2.
            BrunoTitleDateContentView(item: item)
        } else if posterType == .landscape {
            PosterButton<BaseItemDto>.TitleSubtitleContentView(item: item)
        } else {
            // Portrait grid cards: Bruno-wide two-line title (wrap, don't truncate with "…").
            BrunoPosterTitleContentView(item: item)
        }
    }
}

// MARK: - BrunoBoxSetCardLabel

//
// The collection card lockup. Preferred layout puts "{Title} Collection" on line 1 and the film
// count (left) + release-year range (right) on line 2. When "{Title} Collection" is too wide for
// one line, `ViewThatFits` falls back: the title alone on line 1, with "Collection" folded into the
// meta line. Each line reserves its height so grid rows stay aligned.
struct BrunoBoxSetCardLabel: View {

    let item: BaseItemDto
    let yearRange: String?

    private var title: String {
        item.displayTitle.brunoStrippingCollectionSuffix
    }

    private var filmCount: String? {
        guard let count = item.childCount, count > 0 else { return nil }
        return count == 1 ? "1 film" : "\(count) films"
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            layout(line1: "\(title) Collection", collectionInMeta: false)
            layout(line1: title, collectionInMeta: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func layout(line1: String, collectionInMeta: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(line1)
                .font(.footnote.weight(.regular))
                .foregroundColor(.primary)
                .lineLimit(1, reservesSpace: true)

            HStack(spacing: 6) {
                Text(metaLeft(collectionInMeta: collectionInMeta))
                Spacer(minLength: 6)
                // Year range sits a step quieter than the film count.
                if let yearRange { Text(yearRange).opacity(0.6) }
            }
            .font(.caption.weight(.medium))
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
    }

    /// Left side of the meta line: the film count, prefixed with "Collection · " only in the
    /// overflow layout where "Collection" couldn't sit on line 1.
    private func metaLeft(collectionInMeta: Bool) -> String {
        let parts = collectionInMeta
            ? ["Collection", filmCount].compactMap(\.self)
            : [filmCount].compactMap(\.self)
        return parts.joined(separator: " · ")
    }
}

// MARK: - BrunoBoxSetYearRangesViewModel

//
// Fetches each box set's release-year RANGE (min–max of its films) concurrently on demand. The box
// set's own `ProductionYear` is only the start; the range needs the children, so we fetch each
// collection's child years once and cache the formatted string. Boxed Sets only (~dozens of items).
@MainActor
final class BrunoBoxSetYearRangesViewModel: ViewModel {

    @Published
    private(set) var ranges: [String: String] = [:]
    /// Flips true once after all ranges are fetched, so the grid can rebuild a single time.
    @Published
    private(set) var done = false

    private var loaded = false

    func load(items: [BaseItemDto]) {
        guard !loaded, let userSession else { return }
        loaded = true
        let client = userSession.client
        let userID = userSession.user.id
        Task {
            await withTaskGroup(of: (String, String)?.self) { group in
                for item in items {
                    guard let id = item.id else { continue }
                    group.addTask { await Self.range(client: client, userID: userID, id: id) }
                }
                for await result in group {
                    if let result { ranges[result.0] = result.1 }
                }
            }
            done = true
        }
    }

    private nonisolated static func range(client: JellyfinClient, userID: String, id: String) async -> (String, String)? {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.parentID = id
        parameters.includeItemTypes = [.movie]
        parameters.isRecursive = true
        parameters.limit = 200 // ProductionYear is a base field, returned without an explicit Fields request
        do {
            let items = try await client.send(Paths.getItems(parameters: parameters)).value.items ?? []
            let years = items.compactMap(\.productionYear).filter { $0 > 0 }
            guard let lo = years.min(), let hi = years.max() else { return nil }
            return (id, lo == hi ? "\(lo)" : "\(lo)–\(hi)")
        } catch {
            return nil
        }
    }
}

// MARK: - NavigationRoute

extension NavigationRoute {

    @MainActor
    static func brunoBoxSetGrid(
        title: String,
        items: [BaseItemDto],
        posterType: PosterDisplayType,
        collectionLabel: Bool = false,
        artCarousel: Bool = false,
        showsDate: Bool = false,
        oscarCategory: BrunoOscarCategory? = nil,
        oscarParent: BaseItemDto? = nil,
        heroAsset: String? = nil,
        householdNames: [String]? = nil,
        allSectionTitle: String = "All",
        assetOverride: ((BaseItemDto) -> String?)? = nil
    ) -> NavigationRoute {
        NavigationRoute(
            id: "bruno-boxset-grid-\(title.lowercased())",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) }
        ) {
            BrunoBoxSetGridView(
                title: title,
                items: items,
                posterType: posterType,
                collectionLabel: collectionLabel,
                artCarousel: artCarousel,
                showsDate: showsDate,
                oscarCategory: oscarCategory,
                oscarParent: oscarParent,
                heroAsset: heroAsset,
                householdNames: householdNames,
                allSectionTitle: allSectionTitle,
                assetOverride: assetOverride
            )
        }
    }
}

// MARK: - BrunoOscarGridViewModel

//
// Pages the COMPLETE film set of one Oscar category BoxSet (the drill-in shelf only loads a small
// preview), sorted reverse-chronologically by award year for the "Show all" grid. Fetches `.tags` so
// BrunoOscarContentView can read each film's `oscar:` tag. One-shot, memoized — runs once per push.
@MainActor
final class BrunoOscarGridViewModel: ViewModel {

    @Published
    private(set) var items: [BaseItemDto]?

    private var loaded = false

    func load(parent: BaseItemDto, category: BrunoOscarCategory) {
        guard !loaded, let userSession, let parentID = parent.id else { return }
        loaded = true
        let client = userSession.client
        let userID = userSession.user.id
        Task {
            let all = await (try? BrunoItemPaging.fetchAll(client: client) { startIndex, limit in
                var parameters = Paths.GetItemsParameters()
                parameters.userID = userID
                parameters.parentID = parentID
                parameters.includeItemTypes = [.movie]
                // .tags carries oscar:<cat>:<won|nom>:<year> for the caption + reverse-chron sort.
                parameters.fields = .MinimumFields + [.tags]
                parameters.enableUserData = true
                parameters.startIndex = startIndex
                parameters.limit = limit
                return parameters
            }) ?? []
            items = BrunoOscar.reverseChronological(all, category: category)
        }
    }
}
