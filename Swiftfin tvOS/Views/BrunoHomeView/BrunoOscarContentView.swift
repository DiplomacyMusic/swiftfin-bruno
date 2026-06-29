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

// MARK: - BrunoOscarContentView

//
// Oscar shelf / grid poster label: the film title on line 1 and its standing in THIS shelf's Oscar
// category on line 2 — "Winner (1994)" (italic + accent, per owner's "*Winner*") or "Nominee (1994)".
//
// INV-1: a geometry-faithful clone of BrunoRewatchablesContentView / BrunoTitleDateContentView —
// identical container, fonts, and `.lineLimit(1, reservesSpace: true)` on BOTH lines — so the pinned
// shelf-row height is byte-identical. `.italic()` and `.foregroundColor` are paint-only (no effect on
// line metrics), and an absent award still reserves the line, so a film with no `oscar:` tag (e.g.
// before enrich/p9_oscars.py runs) doesn't change the row height. The category is threaded from the
// shelf because Oscar status is per-(film, category): a film can win one category, be nominated in
// another. The award is read from the per-item `oscar:<category>:<won|nom>:<year>` tag.
struct BrunoOscarContentView: View {

    let item: BaseItemDto
    let category: BrunoOscarCategory

    private var award: BrunoOscarAward? {
        BrunoOscar.award(for: category, on: item)
    }

    /// "Winner (1994)" / "Nominee (1994)" — built as a plain String (so the year never picks up a
    /// locale grouping separator) and rendered verbatim. Empty when the film has no tag here.
    private var caption: String {
        guard let award else { return "" }
        return "\(award.won ? "Winner" : "Nominee") (\(award.year))"
    }

    var body: some View {
        VStack(alignment: .leading) {
            if item.showTitle {
                Text(item.displayTitle)
                    .font(.footnote.weight(.regular))
                    .foregroundColor(.primary)
                    .lineLimit(1, reservesSpace: true)
            }

            Text(caption)
                .font(.caption.weight(.medium))
                .italic(award?.won == true)
                .foregroundColor(award?.won == true ? Color.bruno.accent : .secondary)
                .lineLimit(1, reservesSpace: true)

            // TODO(oscars third line): add a THIRD line with the nominated person's name for this
            // category (actor / director / writer / cinematographer / composer). The name is in
            // data/oscars.json (entry.name) but NOT stamped yet — p9_oscars.py must extend the tag to
            // carry it (e.g. oscar:<CAT>:<won|nom>:<YEAR>:<name>; handle 2-acting-noms + BEST_PICTURE
            // having no single person), and BrunoOscar must parse it. INV-1 CAVEAT: this label is a
            // 2-line budget baked into BrunoShelfMetrics.shelfRowHeight — a third line means growing
            // that (shared) height, not just adding a Text. See FEATURE_BACKLOG.md §E1.
        }
    }
}
