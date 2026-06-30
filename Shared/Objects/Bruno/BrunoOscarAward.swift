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

    /// Map a curated BoxSet display name ("Oscar Best Picture", or the legacy "Oscar — Best Picture")
    /// to its category; nil for any non-Oscar name. The canonical Oscar-category predicate — reused by
    /// BrunoBoxSetShelvesView.consolidateOscars and BrunoCuratedCard.titleParts so all three recognize
    /// exactly the six shelves that get the caption. Tolerant of BOTH the em-dash and the space-only
    /// form, so the server rename dropping the dash never breaks recognition; non-category "Oscar …"
    /// names (Oscar Buzz / Oscar Bait) trim to a word the switch doesn't match ⇒ nil, still excluded.
    init?(boxSetName name: String) {
        let lower = name.lowercased()
        guard lower.hasPrefix("oscar") else { return nil }
        let category = lower.dropFirst("oscar".count)
            .trimmingCharacters(in: CharacterSet(charactersIn: " —-"))
        switch category {
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

    /// How many leading slots participate in the cross-shelf lead spread (≈ one poster row).
    private static let leadBand = 6

    /// Spread the LEAD slots across the six category shelves so one recent award year doesn't dominate
    /// the first visible slot of every shelf (plan §4 — the owner's cheap per-shelf heuristic, "just want
    /// some variation," not a full cross-shelf rebalance). Rotates ONLY the top lead band of an already
    /// `reverseChronological` array by a per-category offset; the tail stays strict reverse-chron. The six
    /// categories take distinct offsets (`categoryIndex + seededBase`, mod band) so they don't collide when
    /// the band is full; a `seed`-derived base rotates the whole set per launch. Determinism (INV-3): the
    /// offset is a pure function of `(category, seed)` — no `Date()`, no per-body recompute — so the spread
    /// is stable within a session and varies deterministically across sessions. Approximate by design: two
    /// SPARSE shelves (band < 6) can still occasionally share an offset; accepted.
    static func spreadLeads(_ items: [BaseItemDto], category: BrunoOscarCategory, seed: UInt32) -> [BaseItemDto] {
        let band = min(leadBand, items.count)
        guard band > 1 else { return items }
        let categoryIndex = BrunoOscarCategory.allCases.firstIndex(of: category) ?? 0
        var rng = BrunoRNG(seed: BrunoRNG.subSeed(seed, 131, 0, 0))
        let base = Int(rng.nextUnit() * Double(band))
        let offset = (categoryIndex + base) % band
        guard offset > 0 else { return items }
        var result = items
        let head = Array(items[0 ..< band])
        result.replaceSubrange(0 ..< band, with: head[offset...] + head[..<offset])
        return result
    }
}
