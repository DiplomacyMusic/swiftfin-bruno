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

// MARK: - Home "Show all" routing (D1 + D2)

//
// D1 — "two doors to the same end room": a Home shelf's trailing "Show all" lands on the SAME
// destination as the equivalent browse instance. The unifying idea is simple — every Home shelf
// already carries its destination identity in `shelf.source`, so we route off that:
//
//   • query-backed shelves (genre, studio, director-spotlight, acclaimed, critics, series, classic
//     romance, curated, seasonal, …) → the full paged version of the shelf's OWN query
//     (`BrunoQueryLibrary`). That's literally "the same shelf, expanded".
//   • the three stock spine shelves → their stock full library.
//   • D2: year and single-decade shelves, and the Eras decade tiles, deep-link into the Decades
//     surface with that decade's PILL pre-selected (no new data); the Eras shelf itself opens the
//     Decades overview.
//   • the `.items` group shelves (Eras / Auteurs) → a box-set grid of their children. (The Collections
//     shelf is the exception: it renders the branded category row with per-tile drill-in, no show-all.)
//
// This funnels Home into the same destination kinds the browse `brunoRouteToShowAll` produces, so
// the two surfaces reach the same rooms.
@MainActor
func brunoHomeRouteToShowAll(
    shelf: BrunoShelf,
    snapshot: BrunoLibrarySnapshot,
    router: Router.Wrapper,
    namespace: Namespace.ID
) {
    // The favorited "Decades" group box set — the parent the Decades pill surface drills from.
    let decadesGroup = snapshot.favoriteGroupBoxSets.first { $0.displayTitle.lowercased() == "decades" }

    switch shelf.kind {
    case .resume:
        router.route(to: .library(library: ResumeItemsLibrary()), in: namespace)

    case .nextUp:
        router.route(to: .library(library: NextUpLibrary()), in: namespace)

    case .recentlyAdded:
        router.route(to: .library(library: RecentlyAddedLibrary()), in: namespace)

    case .year:
        // The ±2-year spine shelf → the Decades surface, pill set to the year's decade (2015 → 2010s).
        guard let decadesGroup, case let .query(query) = shelf.source, !query.years.isEmpty else { return }
        let sorted = query.years.sorted()
        let midYear = sorted[sorted.count / 2]
        router.route(to: .brunoCategoryShelves(parent: decadesGroup, decade: "\(midYear / 10 * 10)s"), in: namespace)

    case .decade:
        // The explore decade shelf carries its decade box set as `parentID`; resolve its name and
        // deep-link to that pill.
        guard let decadesGroup, case let .query(query) = shelf.source, let parentID = query.parentID,
              let name = snapshot.decadeBoxSets.first(where: { $0.id == parentID })?.name else { return }
        router.route(to: .brunoCategoryShelves(parent: decadesGroup, decade: name), in: namespace)

    case .eras:
        // The Eras shelf shows every decade tile → open the Decades overview (no specific pill).
        guard let decadesGroup else { return }
        router.route(to: .brunoCategoryShelves(parent: decadesGroup), in: namespace)

    case .auteurs:
        // Same destination as the Collections Directors card: §7 cinematic hero + §5 Household Names.
        router.route(
            to: .brunoBoxSetGrid(
                title: "Directors",
                items: snapshot.directorBoxSets,
                posterType: .portrait,
                artCarousel: true,
                heroAsset: BrunoCollectionArtwork.heroAsset(for: "Directors"),
                householdNames: BrunoBoxSetGridView.recognizableDirectors,
                allSectionTitle: "All Directors"
            ),
            in: namespace
        )

    // NB: `.collections` has no case here — the Home "Browse the Collection" shelf renders the branded
    // BrunoCategoryCardRow (per-tile drill-in via brunoRouteToShowAll), with no trailing "Show all"
    // card, so this router is never reached for it (it would otherwise no-op in `default` anyway, since
    // a collections shelf's source is `.items`, not `.query`).

    default:
        guard case let .query(query) = shelf.source else { return }
        // Captioned curated shelves reach the SAME destination as their browse twins, so the caption
        // (and the Ebert toggle / Oscar reverse-chron) carries through instead of a plain paged grid.
        switch query.caption {
        case .ebertStars:
            let ebert = snapshot.promotedCuratedBoxSets.filter { ($0.name ?? "").lowercased().hasPrefix("ebert") }
            if let up = ebert.first(where: { !($0.name ?? "").lowercased().contains("down") }),
               let down = ebert.first(where: { ($0.name ?? "").lowercased().contains("down") })
            {
                // This shelf is the Down shelf iff its parent BoxSet is the Down BoxSet.
                router.route(to: .brunoEbert(up: up, down: down, showingDown: down.id == query.parentID))
                return
            }
        case let .oscar(category):
            if let parentID = query.parentID,
               let boxSet = snapshot.promotedCuratedBoxSets.first(where: { $0.id == parentID })
            {
                router.route(
                    to: .brunoBoxSetGrid(
                        title: BrunoCuratedCard.display(boxSet.name ?? shelf.title),
                        items: [],
                        posterType: .portrait,
                        oscarCategory: category,
                        oscarParent: boxSet
                    ),
                    in: namespace
                )
                return
            }
        case .none:
            break
        }
        // Every remaining shelf is query-backed: open the full, paged version of its own query — the
        // same films the shelf previews, just the complete grid.
        router.route(
            to: .library(library: BrunoQueryLibrary(query: query, displayTitle: shelf.title, id: shelf.id)),
            in: namespace
        )
    }
}

// swiftlint:enable hard_coded_display_string
