//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// MARK: - Item-detail "Recommended" shelf: Bruno-native filter + routing

//
// The item-detail "Recommended" shelf (`ItemView.SimilarItemsHStack`) renders Jellyfin's raw
// similar-items result, which on Bruno's BoxSet-curated library leaks two kinds of junk:
//   • the top-level NAV HUB BoxSets (Genres / Directors / Decades / Curated / Studios / …) — a whole
//     navigation hub is noise as a per-film "recommendation", and tapping one opens the stock
//     `CollectionItemContentView` grid (the broken "Directors / Director's Cut" screen).
//   • genuine content collections that, via the generic `.item` route, also land on that stock grid.
//
// This classifier maps each similar-items tile to a `BrunoRecommendedTarget`: drop the hubs, keep
// movie/series tiles untouched, and reroute every surviving content collection to the SAME branded
// Bruno destination its browse twin reaches (mirroring `brunoRouteToShowAll` /
// `brunoHomeRouteToShowAll`). Identity is resolved off the warm `BrunoLibrarySnapshot`, so an
// unrecognized BoxSet — or anything seen before the snapshot is warm — is dropped rather than routed
// to a wrong/empty grid. The shelf stays a single homogeneous `PosterHStack`: only which tiles show
// and where a tap lands changes (no card-type/aspect swap — INV-1/-10).
enum BrunoRecommendedTarget {

    /// Movie / series tile — keep the stock detail route (unchanged behavior).
    case item(BaseItemDto)
    /// A decade collection → the Decades pill surface with that decade pre-selected.
    case decade(parent: BaseItemDto, decade: String)
    /// An Ebert curated list → the merged Up ⇄ Down star-captioned toggle grid.
    case ebert(up: BaseItemDto, down: BaseItemDto?, showingDown: Bool)
    /// An Oscar category → the reverse-chron, "Winner/Nominee (Year)"-captioned grid.
    case oscar(category: BrunoOscarCategory, parent: BaseItemDto)
    /// The Rewatchables BoxSet → the flat, episode-captioned portrait grid.
    case rewatchables(BaseItemDto)
    /// A genre collection → its newest-first films grid (matches the browse genre "show all").
    case genreGrid(BaseItemDto)
    /// Any other content collection (director / studio / seasonal / franchise / curated) → a clean
    /// paged films grid scoped to the BoxSet, which also avoids recursing the stock collection view.
    case filmsGrid(BaseItemDto)
    /// A nav hub, or an unresolved BoxSet (incl. cold-start before the snapshot is warm) → not shown.
    case drop
}

// Logic-only string comparisons (group / list identity), not user-facing copy.
// swiftlint:disable hard_coded_display_string

/// Classify one similar-items tile. First match wins.
func brunoRecommendedTarget(_ item: BaseItemDto, snapshot: BrunoLibrarySnapshot) -> BrunoRecommendedTarget {

    // Movies / series keep the stock detail route.
    guard item.type == .boxSet else { return .item(item) }

    let id = item.id

    // Rewatchables lives in `favoriteGroupBoxSets`, but its members are FILMS and it has a branded
    // per-film grid — resolve it before the hub drop below.
    if let rewatchables = snapshot.rewatchablesBoxSet, rewatchables.id == id {
        return .rewatchables(rewatchables)
    }

    // Every other top-level nav hub is navigation scaffolding, not a per-film recommendation.
    if snapshot.favoriteGroupBoxSets.contains(where: { $0.id == id }) {
        return .drop
    }

    // Decade → the pill surface (needs the favorited "Decades" group as the drill parent).
    if snapshot.decadeBoxSets.contains(where: { $0.id == id }),
       let decadesGroup = snapshot.favoriteGroupBoxSets.first(where: { $0.displayTitle.lowercased() == "decades" }),
       let name = item.name
    {
        return .decade(parent: decadesGroup, decade: name)
    }

    // Curated children: Ebert toggle, Oscar captioned grid, else the curated collection's films grid.
    if snapshot.curatedBoxSets.contains(where: { $0.id == id }) {
        if (item.name ?? "").lowercased().hasPrefix("ebert") {
            let ebert = snapshot.curatedBoxSets.filter { ($0.name ?? "").lowercased().hasPrefix("ebert") }
            let down = ebert.first { ($0.name ?? "").lowercased().contains("down") }
            let up = ebert.first { !($0.name ?? "").lowercased().contains("down") } ?? item
            return .ebert(up: up, down: down, showingDown: down?.id == id)
        }
        if let category = BrunoOscarCategory(boxSetName: item.name ?? "") {
            return .oscar(category: category, parent: item)
        }
        return .filmsGrid(item)
    }

    // Genre → newest-first films grid.
    if snapshot.genreBoxSets.contains(where: { $0.id == id }) {
        return .genreGrid(item)
    }

    // Director / Studio / Seasonal / Franchise → clean films grid.
    let franchise = snapshot.franchiseBoxSets ?? []
    if snapshot.directorBoxSets.contains(where: { $0.id == id })
        || snapshot.studioBoxSets.contains(where: { $0.id == id })
        || snapshot.seasonalBoxSets.contains(where: { $0.id == id })
        || franchise.contains(where: { $0.id == id })
    {
        return .filmsGrid(item)
    }

    // Unrecognized BoxSet (or snapshot not yet warm) — don't surface it.
    return .drop
}

// swiftlint:enable hard_coded_display_string

/// The similar-items tiles to actually render: everything except the dropped hubs / unresolved BoxSets,
/// in the endpoint's original order.
func brunoRecommendedDisplayItems(_ items: [BaseItemDto], snapshot: BrunoLibrarySnapshot) -> [BaseItemDto] {
    items.filter {
        if case .drop = brunoRecommendedTarget($0, snapshot: snapshot) { return false }
        return true
    }
}

/// Route a tapped Recommended tile to its branded Bruno destination (or the stock detail for films),
/// reusing the existing `bruno*` routes — none are invented here.
@MainActor
func routeBrunoRecommended(
    _ item: BaseItemDto,
    snapshot: BrunoLibrarySnapshot,
    router: Router.Wrapper,
    namespace: Namespace.ID
) {
    switch brunoRecommendedTarget(item, snapshot: snapshot) {
    case let .item(item):
        router.route(to: .item(item: item))

    case let .decade(parent, decade):
        router.route(to: .brunoCategoryShelves(parent: parent, decade: decade), in: namespace)

    case let .ebert(up, down, showingDown):
        router.route(to: .brunoEbert(up: up, down: down, showingDown: showingDown))

    case let .oscar(category, parent):
        router.route(
            to: .brunoBoxSetGrid(
                title: BrunoCuratedCard.display(parent.name ?? parent.displayTitle),
                items: [],
                posterType: .portrait,
                oscarCategory: category,
                oscarParent: parent
            ),
            in: namespace
        )

    case let .rewatchables(parent):
        router.route(to: .brunoRewatchables(parent: parent))

    case let .genreGrid(boxSet):
        // Newest-first so pre-1985 classics sink to the bottom, matching the browse genre grid.
        router.route(
            to: .library(
                library: ItemLibrary(parent: boxSet, filters: .init(sortBy: [.premiereDate], sortOrder: [.descending]))
            ),
            in: namespace
        )

    case let .filmsGrid(boxSet):
        router.route(to: .library(library: ItemLibrary(parent: boxSet)), in: namespace)

    case .drop:
        break
    }
}
