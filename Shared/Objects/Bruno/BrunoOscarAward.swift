//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

// MARK: - BrunoOscarCategory

//
// The six curated Oscar categories — the `Oscar — <Category>` BoxSets under the Curated group.
// The raw value is the tag key the producer (enrich/p9_oscars.py) writes into the per-item tag
// `oscar:<rawValue>:<won|nom>:<year>`, so the app can render each poster's standing in THIS shelf's
// category (a film can win one category and only be nominated in another) and order reverse-chron.
enum BrunoOscarCategory: String, CaseIterable, Equatable, Hashable {

    case bestPicture = "BEST_PICTURE"
    case directing = "DIRECTING"
    case acting = "ACTING"
    case cinematography = "CINEMATOGRAPHY"
    case score = "SCORE"
    case screenplay = "SCREENPLAY"

    /// Map a curated BoxSet display name ("Oscar — Best Picture") to its category; nil for any
    /// non-Oscar name. Same predicate as BrunoBoxSetShelvesView.consolidateOscars (hasPrefix "oscar"
    /// + the " — " separator), so it recognizes exactly the six shelves that get the caption.
    init?(boxSetName name: String) {
        let lower = name.lowercased()
        guard lower.hasPrefix("oscar"), let separator = lower.range(of: " — ") else { return nil }
        switch lower[separator.upperBound...].trimmingCharacters(in: .whitespaces) {
        case "best picture": self = .bestPicture
        case "directing": self = .directing
        case "acting": self = .acting
        case "cinematography": self = .cinematography
        case "score": self = .score
        case "screenplay": self = .screenplay
        default: return nil
        }
    }
}

// MARK: - BrunoOscarAward

/// A film's standing in one Oscar category, parsed from its `oscar:` item tag.
struct BrunoOscarAward: Equatable {
    let won: Bool
    let year: Int
}

// MARK: - BrunoOscar

enum BrunoOscar {

    static let tagPrefix = "oscar:"

    /// Parse the award for `category` from an item's tags: `oscar:<CAT>:<won|nom>:<YEAR>`. nil when the
    /// film carries no tag for that category — e.g. before p9 runs, or a film not nominated there — in
    /// which case the caption renders a blank (but height-reserving) line.
    static func award(for category: BrunoOscarCategory, on item: BaseItemDto) -> BrunoOscarAward? {
        guard let tags = item.tags else { return nil }
        let needle = tagPrefix + category.rawValue + ":"
        guard let tag = tags.first(where: { $0.hasPrefix(needle) }) else { return nil }
        let parts = tag.split(separator: ":")
        guard parts.count == 4, let year = Int(parts[3]) else { return nil }
        return BrunoOscarAward(won: parts[2] == "won", year: year)
    }

    /// Reverse-chronological order for an Oscar category shelf/grid: newest award year first, then
    /// premiereDate descending, then id (stable tiebreak — INV-3 deterministic, no RNG, no wall-clock).
    /// Films with no tag for the category fall back to their production year so they still sort sensibly.
    static func reverseChronological(_ items: [BaseItemDto], category: BrunoOscarCategory) -> [BaseItemDto] {
        items.sorted { lhs, rhs in
            let leftYear = award(for: category, on: lhs)?.year ?? (lhs.productionYear ?? 0)
            let rightYear = award(for: category, on: rhs)?.year ?? (rhs.productionYear ?? 0)
            if leftYear != rightYear { return leftYear > rightYear }
            let leftDate = lhs.premiereDate ?? .distantPast
            let rightDate = rhs.premiereDate ?? .distantPast
            if leftDate != rightDate { return leftDate > rightDate }
            return (lhs.id ?? "") < (rhs.id ?? "")
        }
    }
}
