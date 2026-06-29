//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

// MARK: - BrunoEbert

//
// Roger Ebert's star rating for a film, read from its `ebert-stars:<n>` item tag (the tag the producer
// stamps; 0–4 in half steps). The mirror of `BrunoOscar` (BrunoOscarAward.swift): a tiny tolerant parse +
// a deterministic ordering used by the Ebert shelves' caption (BrunoEbertContentView) and their
// score-ordered layout (Thumbs Up = highest first, Thumbs Down = lowest first).
enum BrunoEbert {

    static let tagPrefix = "ebert-stars:"

    /// The film's Ebert rating (0–4), or nil when it carries no `ebert-stars:` tag (never reviewed, or
    /// before Apply-Enrich-Tags runs) — in which case the caption is blank and the film sorts last.
    static func stars(on item: BaseItemDto) -> Double? {
        guard let tag = item.tags?.first(where: { $0.hasPrefix(tagPrefix) }),
              let value = Double(tag.dropFirst(tagPrefix.count)), value >= 0
        else { return nil }
        return value
    }

    /// Order films by Ebert rating: `ascending` false ⇒ highest first (the Thumbs Up shelf), true ⇒
    /// lowest first (the Thumbs Down shelf). Untagged films always sink to the bottom (no rating to rank).
    /// Tiebreak: premiereDate descending, then id — deterministic, no RNG, no wall-clock (INV-3 safe).
    static func ordered(_ items: [BaseItemDto], ascending: Bool) -> [BaseItemDto] {
        items.sorted { lhs, rhs in
            switch (stars(on: lhs), stars(on: rhs)) {
            case let (l?, r?):
                if l != r { return ascending ? l < r : l > r }
            case (.some, nil):
                return true // tagged before untagged
            case (nil, .some):
                return false
            case (nil, nil):
                break
            }
            let leftDate = lhs.premiereDate ?? .distantPast
            let rightDate = rhs.premiereDate ?? .distantPast
            if leftDate != rightDate { return leftDate > rightDate }
            return (lhs.id ?? "") < (rhs.id ?? "")
        }
    }
}
