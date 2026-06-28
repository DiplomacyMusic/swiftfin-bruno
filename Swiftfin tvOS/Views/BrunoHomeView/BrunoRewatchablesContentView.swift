//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// MARK: - BrunoRewatchablesContentView

//
// Bruno-LOCAL poster label for the Rewatchables surface: title + "Episode NN", where NN is parsed from
// the producer-written `rewatchables-ep:NN` item tag (the same tag family as `bruno-sig:NN`). A
// deliberate, geometry-faithful clone of BrunoTitleDateContentView (itself a clone of the shared
// PosterButton.TitleSubtitleContentView) so INV-1's pinned BrunoShelfMetrics.shelfRowHeight holds with
// NO height change — same VStack(.leading), same title font/opacity, same .lineLimit(1, reservesSpace:
// true) on BOTH lines. The only divergence is line 2: the episode label in place of the date. A film
// with no tag (e.g. Scarface, never covered by the podcast) renders a blank 2nd line, preserving the
// reserved-space geometry. Do NOT modify the shared view.
struct BrunoRewatchablesContentView: View {

    let item: BaseItemDto

    private static let tagPrefix = "rewatchables-ep:"

    /// Parse `rewatchables-ep:NN` → "Episode NN". Absent/empty ⇒ "" (blank line 2, space still reserved).
    private var episodeString: String {
        guard let tag = item.tags?.first(where: { $0.hasPrefix(Self.tagPrefix) }) else { return "" }
        let value = tag.dropFirst(Self.tagPrefix.count)
        return value.isEmpty ? "" : "Episode \(value)"
    }

    var body: some View {
        VStack(alignment: .leading) {
            if item.showTitle {
                Text(item.displayTitle)
                    .font(.footnote.weight(.regular))
                    .foregroundColor(.primary)
                    .lineLimit(1, reservesSpace: true)
            }

            Text(episodeString)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
                .lineLimit(1, reservesSpace: true)
        }
    }
}
