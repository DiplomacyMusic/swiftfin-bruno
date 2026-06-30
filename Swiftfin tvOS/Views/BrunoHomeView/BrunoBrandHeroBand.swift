//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// Prototype copy is English-only; localization (L10n) is a deferred TODO (see BRUNO_NOTES.md).
// swiftlint:disable hard_coded_display_string

// MARK: - BrunoBrandHeroBand

//
// The shared cinematic "brand hero" frame for the Collections drill-in grids (Directors / Movie
// Stars / Box Sets — plan §7). Extracted from BrunoStudiosGridView's body line-for-line so the look
// is identical and there is exactly ONE copy of the band, not one per grid (the anti-scatter rule,
// plan §7): a full-bleed backdrop still filling the screen, a tall transparent hero header (screen
// height − 150) carrying the title, the caller's scrolling content (the grid + any shortlist) below,
// and the SAME BlurView(.dark) + descending gradient mask on the scrolling stack so colors descend
// behind the grid as it scrolls up.
//
// Perf: like Studios, this deliberately uses the ScrollView-`.background` blur INV-6 cautions about
// for recycling grids — that scroll-coupled blur IS the descending-colors effect, and matching the
// detail-page look is the explicit ask. The hero backdrop itself is a static `Image` (no added
// scroll-coupled cost). The grids that adopt this are bounded (dozens of tiles) and use a lazy
// LazyVGrid in the content, so only visible cells realize. (BrunoStudiosGridView / BrunoRewatchablesView
// still hold their own bespoke bands — pre-existing; folding them onto this is a follow-up.)
//
// `backdropAsset` is an asset-catalog name (Image(_:) loads the still; the app's ImageView is
// URL-only and can't). For §7 it's the category's existing card art as a stand-in, easy to swap for
// bespoke hero art later.
struct BrunoBrandHeroBand<Content: View>: View {

    let title: String
    let backdropAsset: String
    @ViewBuilder
    let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Full-bleed backdrop — fills the entire screen, no band, no inset (mirrors the
                // detail page's ImageView layer).
                Image(backdropAsset)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                            .frame(height: proxy.size.height - 150)
                            .padding(.bottom, 50)

                        content()
                    }
                    .background {
                        BlurView(style: .dark)
                            .mask {
                                VStack(spacing: 0) {
                                    LinearGradient(gradient: Gradient(stops: [
                                        .init(color: .white, location: 0),
                                        .init(color: .white.opacity(0.7), location: 0.4),
                                        .init(color: .white.opacity(0), location: 1),
                                    ]), startPoint: .bottom, endPoint: .top)
                                        .frame(height: proxy.size.height - 150)

                                    Color.white
                                }
                            }
                    }
                }
            }
        }
        .ignoresSafeArea()
        // Draw our own cinematic title instead of the system nav title (other full-screen Bruno
        // surfaces suppress it the same way).
        .toolbar(.hidden, for: .navigationBar)
    }

    // The title, bottom-left over the backdrop — the place the detail page puts the logo/title.
    private var header: some View {
        VStack(alignment: .leading) {
            Spacer()
            Text(title)
                .font(.brunoDisplay(72, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 50)
    }
}

// MARK: - BrunoBrandHeroSectionTitle

//
// A small left-aligned section title for the cinematic grids ("Household Names" / "All Directors"),
// matching the house shelf-header style (brunoDisplay ~40, semibold), kerned in from the card edge.
// Standalone (not a method) so both BrunoBrandHeroBand callers and the grid content can use it.
struct BrunoBrandHeroSectionTitle: View {

    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.brunoDisplay(40, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, EdgeInsets.edgePadding)
            .padding(.bottom, 24)
    }
}
