//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreGraphics

// MARK: - BrunoShelfMetrics

//
// Single source of truth for the load-bearing layout/image constants that the Bruno tvOS
// perf invariants depend on. Centralized so a UX-polish change can't desync the two sites
// that MUST agree (the shelf-row height pin; the poster request width vs the prefetch width).
//
// See docs/BRUNO_PERF_INVARIANTS.md — these back INV-1 and INV-4. Change the value HERE and
// every consumer follows; never hardcode these numbers at a call site.
enum BrunoShelfMetrics {

    // INV-1: Fixed shelf-row height. Pins each shelf so the LazyVStack never re-reads
    // CollectionHStack's intrinsic size on vertical focus moves (the up/down hitch / "hard snap")
    // AND so the spine geometry stays constant while shelves stream/reconcile under live focus. Read
    // by BrunoShelfView and BrunoShelfRow. Break symptom: hitch returns / rows shift under the cursor.
    //
    // PORTRAIT (7 columns): card ~241w x 3/2 = ~362h + ~58 two-line label + 40 vertical insets ≈ 460.
    static let shelfRowHeight: CGFloat = 460

    // INV-1 (landscape): landscape shelves are 4-column (PosterHStack), so the card is far larger
    // and MUST be pinned too — leaving it intrinsic made landscape rows hard-snap on up-navigation.
    // LANDSCAPE (4 columns): card ~440w / 1.77 = ~249h + ~58 two-line label + 40 vertical insets ≈ 347.
    static let landscapeShelfRowHeight: CGFloat = 348

    // INV-1 (collections row): the "Browse the Collection" category cards (BrunoCategoryTile) are
    // portrait tiles with the label drawn ON the card, so the row has NO under-card label — it's the
    // portrait card height + vertical insets WITHOUT the ~58pt two-line-label reserve the poster rows
    // carry. PORTRAIT (7 columns): card ~362h + 40 vertical insets ≈ 402. Pins BrunoCategoryCardRow in
    // the Home spine so the LazyVStack never re-reads CollectionHStack's intrinsic size (same contract
    // as shelfRowHeight). Break symptom: the collections row hard-snaps / shifts on up-navigation.
    static let categoryRowHeight: CGFloat = 402

    /// The pinned row height for a shelf of the given poster type.
    static func shelfRowHeight(for type: PosterDisplayType) -> CGFloat {
        type == .landscape ? landscapeShelfRowHeight : shelfRowHeight
    }

    // INV-4: Poster request width must equal the width the prefetcher warms, or the Nuke cache key
    // (salted by maxWidth) misses and prefetch silently warms nothing. These MIRROR the stock-private
    // constants in Shared/Components/PosterImage.swift (portrait 200 / landscape 300, quality 90) —
    // the width the home/browse poster CELLS actually request. This is a mirror, not the owning knob
    // (the cell's width lives in stock PosterImage); if PosterImage's defaults ever change, update here.
    static let portraitPosterMaxWidth: CGFloat = 200
    static let landscapePosterMaxWidth: CGFloat = 300
    static let posterQuality: Int = 90

    /// The poster request width for a given display type — used by the Bruno prefetch feeder so it
    /// requests the exact `ImageSource` the cell will later request (INV-4).
    static func posterMaxWidth(for type: PosterDisplayType) -> CGFloat {
        type == .landscape ? landscapePosterMaxWidth : portraitPosterMaxWidth
    }

    // Portrait headroom: the focused poster scales up under the borderless/card focus style and, at the
    // leading edge (continuousLeadingEdge), the focused FIRST cell grows UP into the eyebrow+title that
    // sits directly above it. Reserve extra space below a portrait shelf's header so the scaled cell-1
    // clears the title. Tall portrait cards (~362h) collide; short landscape cards (~249h) don't, so
    // this offset is portrait-only. NOT an INV constant — it doesn't touch the pinned row height.
    static let portraitHeaderBottomInset: CGFloat = 20
}
