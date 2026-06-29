//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// MARK: - BrunoEbertContentView

//
// Ebert shelf poster label: the film title on line 1 and Roger Ebert's star rating on line 2, rendered
// as four star glyphs (e.g. "★★★½") parsed from the producer-written `ebert-stars:<n>` item tag (the
// same tag family as `oscar:` / `rewatchables-ep:`). A film with no tag (never reviewed) renders a blank
// 2nd line.
//
// INV-1: a geometry-faithful clone of BrunoOscarContentView / BrunoRewatchablesContentView /
// BrunoTitleDateContentView — identical container, fonts, and `.lineLimit(1, reservesSpace: true)` on
// BOTH lines — so the pinned shelf-row height is byte-identical. The stars are PLAIN unicode characters
// in a `Text` with the same `.caption.weight(.medium)` as the other labels' line 2 (NOT
// `Image(systemName:)`, whose box is not governed by `lineLimit` and could drift the pinned height), so
// line-2 height equals a plain caption line regardless of contents. An absent rating still reserves the
// line, so a film with no `ebert-stars:` tag (e.g. before Apply-Enrich-Tags runs) doesn't change the
// row height. Do NOT modify the shared view.
struct BrunoEbertContentView: View {

    let item: BaseItemDto

    private static let tagPrefix = "ebert-stars:"

    // Ebert's scale is 0–4 in half steps. Render four fixed slots so every rated film shows a uniform-width
    // row (full ★ / half ½ / empty ☆), which reads as a rating and stays distinct from a blank (un-rated) line.
    private var starsString: String {
        guard let tag = item.tags?.first(where: { $0.hasPrefix(Self.tagPrefix) }),
              let raw = Double(tag.dropFirst(Self.tagPrefix.count)), raw >= 0
        else { return "" }

        let halfSteps = Int((min(raw, 4) * 2).rounded()) // 0...8
        let full = halfSteps / 2
        let hasHalf = halfSteps % 2 == 1
        let empty = 4 - full - (hasHalf ? 1 : 0)
        return String(repeating: "★", count: full) + (hasHalf ? "½" : "") + String(repeating: "☆", count: empty)
    }

    var body: some View {
        VStack(alignment: .leading) {
            if item.showTitle {
                Text(item.displayTitle)
                    .font(.footnote.weight(.regular))
                    .foregroundColor(.primary)
                    .lineLimit(1, reservesSpace: true)
            }

            Text(starsString)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .lineLimit(1, reservesSpace: true)
        }
    }
}
