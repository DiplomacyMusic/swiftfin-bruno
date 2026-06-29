//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

// MARK: - BrunoShelfCaption

//
// The per-poster second line a Bruno shelf renders. `.tags` is fetched (in BrunoQueryLibrary) only when
// this is non-`.none`, and BrunoShelfView switches the portrait label on it. Lets a Home curated shelf
// carry the same star / "Winner (Year)" caption the browse Ebert/Oscar shelves show.
enum BrunoShelfCaption: Equatable {
    case none
    /// Roger Ebert star rating (BrunoEbertContentView) — reads the `ebert-stars:` tag.
    case ebertStars
    /// Oscar standing for one category (BrunoOscarContentView) — reads the `oscar:<cat>:` tag.
    case oscar(BrunoOscarCategory)

    var needsTags: Bool {
        self != .none
    }

    /// Derive from a curated BoxSet name: "Oscar — Best Picture" → `.oscar`; "Ebert *" → `.ebertStars`;
    /// anything else → `.none`.
    init(curatedName name: String) {
        if let category = BrunoOscarCategory(boxSetName: name) {
            self = .oscar(category)
        } else if name.lowercased().hasPrefix("ebert") {
            self = .ebertStars
        } else {
            self = .none
        }
    }
}

// MARK: - BrunoQuery

//
// A pure, value-type description of a `GetItems` request for a Bruno shelf. It maps to
// `Paths.GetItemsParameters` in `BrunoQueryLibrary` using ONLY verified SDK fields
// (see BRUNO_NOTES.md §SDK). Determinism contract (PRODUCT_SPEC §4 / plan §D): the server
// sort MUST be stable (`.sortName` / `.premiereDate` / `.communityRating`) and reproducibility
// comes from a CLIENT-SIDE seeded shuffle (`shuffleSeed`) — never `sortBy = [.random]`.
struct BrunoQuery {

    var includeItemTypes: [BaseItemKind] = [.movie]
    var genres: [String] = []
    var studioIDs: [String] = []
    var personIDs: [String] = []
    /// Explicit production-year inclusion set (Jellyfin's `Years` param). The plan expands a
    /// year BOUND into this list against the snapshot's known years (see
    /// `BrunoHomePlan.yearsInRange`) — e.g. Classic Romance fills it with the pre-1985 years and
    /// the regular Romance lens with 1985-onward — because GetItems has no min/max year parameter.
    var years: [Int] = []
    var parentID: String?
    var minCommunityRating: Double?

    /// `Filters=IsUnplayed` / `Filters=IsFavorite`.
    var isUnplayed: Bool = false
    var isFavorite: Bool = false

    /// Stable server sort. Avoid `.random` for shelves meant to reproduce across calls.
    var sortBy: [ItemSortBy] = [.sortName]
    var sortOrder: [JellyfinAPI.SortOrder] = [.ascending]

    var limit: Int = 60

    /// When set, the fetched page is seed-shuffled client-side so the shelf is reproducible.
    var shuffleSeed: UInt32?

    /// Whether to request `BaseItemPerson`/overview-rich fields (heavier). Off by default.
    var richFields: Bool = false

    /// The per-poster caption this shelf renders (star rating / Oscar standing). Drives the `.tags`
    /// fetch (BrunoQueryLibrary) and the portrait render switch (BrunoShelfView). Default `.none`.
    var caption: BrunoShelfCaption = .none

    var itemFilters: [JellyfinAPI.ItemFilter] {
        var f: [JellyfinAPI.ItemFilter] = []
        if isUnplayed { f.append(.isUnplayed) }
        if isFavorite { f.append(.isFavorite) }
        return f
    }
}
