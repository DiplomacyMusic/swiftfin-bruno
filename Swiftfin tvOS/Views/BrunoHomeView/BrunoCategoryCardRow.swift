//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import JellyfinAPI
import SwiftUI

// Prototype copy is English-only; localization (L10n) is a deferred TODO (see BRUNO_NOTES.md).
// swiftlint:disable hard_coded_display_string

// MARK: - BrunoCategoryCardRow

//
// The big gradient category cards (code-drawn `BrunoCategoryTile`, not the group's server poster, so
// every label renders at a controlled size and the synthetic "Boxed Sets" tile gets real art). Shared
// by the Collections/Genres browse surface (`BrunoCategoryShelves`) and the Home feed's terminal
// footer, so a tapped tile drills to the SAME destination from either host (`brunoRouteToShowAll`).
// CollectionHStack (the same primitive `BrunoShelfRow` uses) keeps native tvOS focus scaling +
// continuous-leading-edge scroll; `.card` owns focus so the tile itself stays pure drawing.
struct BrunoCategoryCardRow: View {

    let categories: [BrunoCollectionCategory]
    /// §2: when true (Collections hub only), the strip splits into TWO equal-height rows — Row 1
    /// "what to watch" (curated/marquee), Row 2 "how to browse" (structural hubs) — each its own
    /// `.focusSection()` so up/down hops between rows and left/right stays within a row. Default false
    /// keeps the single strip for every other host (the Home footer/spine, the gold-tile sub-row, and
    /// the Oscars/Cities drill-in card rows, which all share this view).
    var twoRow: Bool = false

    @Router
    private var router

    @Namespace
    private var namespace

    /// Row 1 order (lowercased group names) for the two-row Collections layout — the "how to browse"
    /// lane. Row 2 order is the curated/marquee lane. EXPLICIT order (owner placement, 2026-06-30) —
    /// supersedes the incoming rank order for the two-row layout. Any group not listed in either row
    /// falls to the end of Row 2. Membership/order is the owner's call — edit here.
    private static let row1Order: [String] = [
        "new releases", "directors", "movie stars", "decades", "studios", "boxed sets", "cities",
    ]
    private static let row2Order: [String] = [
        "roger ebert", "rewatchables", "oscars", "seasonal", "asian cinema",
        "film school classics", "critically acclaimed",
    ]

    var body: some View {
        if twoRow {
            VStack(spacing: 0) {
                row(Self.ordered(categories, by: Self.row1Order))
                row(Self.ordered(categories, by: Self.row2Order, appendUnlisted: true))
            }
        } else {
            row(categories)
        }
    }

    // Reorders `items` to match `order` (by lowercased name); unlisted items are dropped unless
    // `appendUnlisted`, in which case they're appended in their incoming order (Row 2's catch-all).
    private static func ordered(
        _ items: [BrunoCollectionCategory],
        by order: [String],
        appendUnlisted: Bool = false
    ) -> [BrunoCollectionCategory] {
        let byName = Dictionary(items.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        var result = order.compactMap { byName[$0] }
        if appendUnlisted {
            let placed = Set(order)
            result += items.filter { !placed.contains($0.name.lowercased()) }
        }
        return result
    }

    // One horizontal card strip — shared by the single-row and two-row layouts so the tile, focus
    // scaling, and routing are byte-identical between them.
    private func row(_ items: [BrunoCollectionCategory]) -> some View {
        CollectionHStack(
            uniqueElements: items,
            columns: 7
        ) { category in
            Button {
                brunoRouteToShowAll(category, router: router, namespace: namespace)
            } label: {
                BrunoCategoryTile(category: category)
            }
            .buttonStyle(.card)
        }
        .clipsToBounds(false)
        .dataPrefix(items.count)
        .insets(horizontal: EdgeInsets.edgePadding, vertical: 20)
        .itemSpacing(EdgeInsets.edgePadding - 20)
        .scrollBehavior(.continuousLeadingEdge)
        .focusSection()
    }
}

// MARK: - Shared "Show all" routing

//
// "Show all" routing for a collection category — used by BOTH `BrunoCategoryCardRow` (the gradient
// tiles, on Collections and the Home footer) and each shelf header's "Show all" in
// `BrunoCategoryShelves`. Kept in one place so the two entry points can never diverge.
@MainActor
func brunoRouteToShowAll(
    _ category: BrunoCollectionCategory,
    router: Router.Wrapper,
    namespace: Namespace.ID
) {
    switch category.drillStyle {
    case .genres:
        router.route(to: .brunoGenres(parent: category.boxSet, core: nil))
    case .shelves:
        // The "Roger Ebert" group tile opens the MERGED toggle grid (Up ⇄ Down) instead of a
        // shelf-per-child drill-in. Resolve up/down from its children by name (the "down" one is
        // Thumbs Down); fall back to the stub if a child is missing. (§1: repointed from the retired
        // synthetic "curated-ebert" id to the real favorited group's name.)
        if category.name.lowercased() == "roger ebert" {
            let down = category.children.first { $0.displayTitle.lowercased().contains("down") }
            let up = category.children.first { !$0.displayTitle.lowercased().contains("down") } ?? category.boxSet
            router.route(to: .brunoEbert(up: up, down: down))
            return
        }
        // Pass the category's own children as the sub-groups so a SYNTHETIC parent (the "Oscars" tile,
        // a label-only stub with no server children) still renders; real group tiles (Decades/Curated)
        // pass their snapshot children, which is exactly what the drill-in would otherwise fetch.
        router.route(to: .brunoCategoryShelves(parent: category.boxSet, subGroups: category.children), in: namespace)
    case .items:
        // Boxed Sets: landscape cards so the franchise names aren't scrunched, with the
        // collection-name / "Collection" / film-count + year-range lockup. §7: cinematic hero band
        // (stand-in = the Boxed Sets card art).
        router.route(
            to: .brunoBoxSetGrid(
                title: category.name,
                items: category.children,
                posterType: .landscape,
                collectionLabel: true,
                heroAsset: BrunoCollectionArtwork.heroAsset(for: category.name)
            ),
            in: namespace
        )
    case .rewatchables:
        // The favorited "Rewatchables" BoxSet: open the flat, episode-captioned portrait grid.
        router.route(to: .brunoRewatchables(parent: category.boxSet))
    case .grid:
        // Oscar category "Show all": route to the captioned, reverse-chron Bruno grid. The stock
        // ItemLibrary (the `.boxSet` branch below) can't render the per-poster "Winner/Nominee (Year)"
        // line, so — like the New Releases redirect — we own the grid. `oscarParent` pages the FULL
        // category; the sorted preview children give an instant first paint.
        if let oscarCategory = BrunoOscarCategory(boxSetName: category.name) {
            router.route(
                to: .brunoBoxSetGrid(
                    title: BrunoCuratedCard.display(category.name),
                    items: BrunoOscar.reverseChronological(category.children, category: oscarCategory),
                    posterType: .portrait,
                    oscarCategory: oscarCategory,
                    oscarParent: category.boxSet
                ),
                in: namespace
            )
            return
        }

        // A lone Ebert BoxSet surfaced outside the consolidated tile (e.g. a Home explore shelf):
        // open the single-set grid (no toggle — `down: nil`), still score-ordered + star-captioned.
        if category.name.lowercased().hasPrefix("ebert") {
            router.route(to: .brunoEbert(up: category.boxSet, down: nil))
            return
        }

        // Dated flat-movie group (New Releases): route to the Bruno-owned grid so posters carry the
        // full release date — the shared stock paged library can't, and editing it would leak dates
        // app-wide. Newest-first so it reads as "new releases". (No box-set children here.)
        if category.showsDate, !category.children.contains(where: { $0.type == .boxSet }) {
            router.route(
                to: .brunoBoxSetGrid(
                    title: category.name,
                    items: category.children.sorted {
                        ($0.premiereDate ?? .distantPast) > ($1.premiereDate ?? .distantPast)
                    },
                    posterType: .portrait,
                    showsDate: true
                ),
                in: namespace
            )
            return
        }

        // Per-year decade shelf: route to a live, fully-paged ItemLibrary scoped to the REAL
        // decade BoxSet, filtered to this single year (the inline row is only a preview, so
        // "Show all" must reach the complete year). The synthetic category's own `boxSet` is a
        // label-only stub, so we can't derive the parent from it — `gridParent` carries the real
        // decade BoxSet and `gridYear` the year. "Other" has no single year (gridYear == nil), so
        // it opens the decade's full library unfiltered.
        if let gridParent = category.gridParent {
            let filters: ItemFilterCollection = category.gridYear.map { year in
                .init(years: [ItemYear(integerLiteral: year)])
            } ?? .default
            router.route(
                to: .library(library: ItemLibrary(parent: gridParent, filters: filters)),
                in: namespace
            )
            return
        }

        // A group whose children are sub-collections (Directors, Studios, …) must show ONLY
        // those box sets on "Show all". The stock ItemLibrary(parent:) query returns the
        // group's movies recursively as well — that's the "all the contributing movies are
        // listed after the directors" bug. Render a static grid of just the box-set children
        // instead (same filter the inline shelf uses). Flat movie groups (no box-set children,
        // e.g. New Releases) keep the live, paged library.
        let boxSetChildren = category.children.filter { $0.type == .boxSet }
        if boxSetChildren.isNotEmpty {
            // Studios get the cinematic Hollywood-backdrop grid (landscape cards under a
            // detail-page-style hero band). Directors stay the plain portrait grid (headshots,
            // header-overlap fix).
            let isStudios = category.name.lowercased() == "studios"
            if isStudios {
                router.route(
                    to: .brunoStudiosGrid(
                        title: category.name,
                        items: boxSetChildren
                    ),
                    in: namespace
                )
            } else {
                // Directors / Movie Stars (and any other box-set-child group): §7 cinematic hero band
                // with the category's card art as the stand-in. Directors additionally get the §5
                // "Household Names" marquee shortlist above the A–Z grid.
                let isDirectors = category.name.lowercased() == "directors"
                router.route(
                    to: .brunoBoxSetGrid(
                        title: category.name,
                        items: boxSetChildren,
                        posterType: .portrait,
                        artCarousel: true,
                        heroAsset: BrunoCollectionArtwork.heroAsset(for: category.name),
                        householdNames: isDirectors ? BrunoBoxSetGridView.recognizableDirectors : nil,
                        allSectionTitle: "All \(category.name)"
                    ),
                    in: namespace
                )
            }
        } else if category.boxSet.libraryType == .boxSet {
            // Genre grids sort newest-first so the pre-1985 classics sink to the literal bottom
            // of the barrel (owner request) — still reachable, just never up top. Other grids
            // keep the default sortName order.
            let filters: ItemFilterCollection = category.recencyBiased
                ? .init(sortBy: [.premiereDate], sortOrder: [.descending])
                : .default
            router.route(
                to: .library(library: ItemLibrary(parent: category.boxSet, filters: filters)),
                in: namespace
            )
        } else {
            // Not a BoxSet: ItemLibrary(parent:) would fall through to an unscoped, whole-
            // library query, so open the item detail instead.
            router.route(to: .item(item: category.boxSet))
        }
    }
}
