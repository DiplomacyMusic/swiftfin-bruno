//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// MARK: - BrunoPosterTitleContentView

//
// Bruno-wide rule for PORTRAIT poster labels: a long title wraps onto a SECOND line instead of
// truncating to one line with an ellipsis ("How to Make a…"). A geometry-faithful Bruno-local clone
// of the shared PosterButton.TitleSubtitleContentView (Components/PosterButton.swift) — same
// VStack(.leading), same title font/weight/color — except the title takes up to two lines and there
// is no subtitle line. Net reserved height is unchanged: the shared view reserves title(1) +
// subtitle(1); this reserves title(2). That two-line footnote block is exactly what BrunoShelfMetrics
// already budgets ("~58 two-line label", INV-1) and what the "Show all" card reserves, so the pinned
// shelf-row height holds with NO change. The shared view is left untouched (it is also used by stock
// tvOS surfaces); Bruno's portrait cells opt in by using THIS view instead.
//
// Used by every Bruno PORTRAIT poster cell: the A–Z grids (BrunoPosterGrid), the home/collection
// shelves (BrunoShelfRow, portrait BrunoShelfView), and the portrait box-set/grid cards. Landscape
// cards (Studios/Directors, landscape shelves) keep the shared label — their titles are short names,
// not the spillover case this rule addresses.
struct BrunoPosterTitleContentView: View {

    let item: BaseItemDto

    var body: some View {
        VStack(alignment: .leading) {
            if item.showTitle {
                Text(item.displayTitle)
                    .font(.footnote.weight(.regular))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
                    .accessibilityLabel(item.displayTitle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
