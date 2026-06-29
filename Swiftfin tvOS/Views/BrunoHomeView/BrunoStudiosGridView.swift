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

// MARK: - BrunoStudiosGridView (tvOS only)

//
// The Studios "Show all" screen, built as a LITERAL copy of the stock item detail page
// (ItemView.CinematicScrollView) — that's the "in-studio focus" look the owner wants applied to the
// parent selection screen. Same structure, line-for-line:
//   • a full-bleed backdrop image filling the whole screen, edge to edge (here a fixed Hollywood-sign
//     still instead of the per-item backdrop),
//   • a tall hero header (screen height − 150) with the "Studios" title over it,
//   • the grid of studio cards as the scrolling content,
//   • the SAME BlurView(.dark) + gradient-mask `.background` on the scrolling stack, so as you scroll
//     up the image blurs and its colors descend behind the grid.
//
// NOTE on perf: this deliberately uses the ScrollView-`.background` blur that INV-6
// (docs/BRUNO_PERF_INVARIANTS.md) cautions against for recycling grids — because that scroll-coupled
// blur IS the descending-colors effect, and matching the detail page exactly is the explicit ask.
// The grid is a lazy LazyVGrid (only visible cells realize) over ~92 studios; if scroll ever feels
// heavy, the lever is the header height / blur, not the structure.
struct BrunoStudiosGridView: View {

    let title: String
    let items: [BaseItemDto]

    @Router
    private var router

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: EdgeInsets.edgePadding),
        count: 4
    )

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Full-bleed backdrop — fills the entire screen, no band, no inset (mirrors the
                // detail page's ImageView layer). Image(_:) loads the asset-catalog still; the app's
                // ImageView is URL-only and can't.
                Image("BrunoStudiosBackdrop")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                            .frame(height: proxy.size.height - 150)
                            .padding(.bottom, 50)

                        // Top: the curated, daily-rotated "Household Names" — only the recognizable
                        // studios, ≤20, with a stable membership whose on-screen order reshuffles
                        // each day (same rotating-seed idea as the Home spotlight).
                        if topStudios.isNotEmpty {
                            sectionTitle("Household Names")
                            grid(for: topStudios)
                        }

                        // Beneath: the full studios grid, unchanged — every studio in alphanumeric
                        // (server) order, the top names intentionally NOT excluded.
                        sectionTitle("All Studios")
                        grid(for: items)
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

    // MARK: Header

    // The "Studios" title, bottom-left over the backdrop — the place the detail page puts the studio
    // logo/title.
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

    // A small left-aligned shelf title, matching the house shelf-header style
    // (BrunoShelfView uses brunoDisplay ~36-40, semibold), kerned in from the card edge.
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.brunoDisplay(40, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, EdgeInsets.edgePadding)
            .padding(.bottom, 24)
    }

    // MARK: Grid

    // Landscape studio cards, 4 across — same cells as before, just laid out in a LazyVGrid so they
    // can live inside the cinematic ScrollView. Parameterized so the top and full sections share it.
    private func grid(for studios: [BaseItemDto]) -> some View {
        LazyVGrid(columns: columns, spacing: EdgeInsets.edgePadding) {
            ForEach(studios, id: \.id) { item in
                BrunoArtCarouselCard(item: item, type: .landscape) {
                    router.route(to: .item(item: item))
                } label: {
                    PosterButton<BaseItemDto>.TitleSubtitleContentView(item: item)
                }
            }
        }
        .padding(.horizontal, EdgeInsets.edgePadding)
        .padding(.bottom, 50)
    }

    // MARK: Top studios (curated + daily-seeded rotation)

    // The most recognizable studio names, in rough editorial order (household recognition ≈
    // cumulative awards + box office — revenue/awards aren't on BaseItemDto app-side, so this list
    // IS the ranking). Only the names actually present in `items` surface; the first ≤20 by this
    // order form a stable membership, and the day-seed rotates their on-screen order so the shelf
    // feels fresh daily without ever dropping a major. Matched case-/punctuation-insensitively.
    private static let recognizableStudios: [String] = [
        "Walt Disney Pictures",
        "Warner Bros. Pictures",
        "Universal Pictures",
        "Paramount Pictures",
        "Columbia Pictures",
        "20th Century Fox",
        "Metro-Goldwyn-Mayer",
        "Marvel Studios",
        "Pixar",
        "Lucasfilm Ltd.",
        "DreamWorks Pictures",
        "DreamWorks Animation",
        "New Line Cinema",
        "Lionsgate",
        "United Artists",
        "TriStar Pictures",
        "Touchstone Pictures",
        "A24",
        "Miramax",
        "Studio Ghibli",
        "Focus Features",
        "Searchlight Pictures",
        "Fox Searchlight Pictures",
        "Legendary Pictures",
        "Amblin Entertainment",
        "Summit Entertainment",
        "The Weinstein Company",
        "Annapurna Pictures",
        "Working Title Films",
        "TOHO",
        "StudioCanal",
        "Marvel Entertainment",
    ]

    private static let topStudioLimit = 20

    // Lowercase + keep only alphanumerics, so "Warner Bros. Pictures" matches "warnerbrospictures"
    // and "A24"/"20th Century Fox" keep their digits (mirrors the producer's `norm`).
    private static func normalizeStudio(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // Day-stamp seed (year*10000 + month*100 + day): stable within a calendar day, rotates each new
    // day — the same per-day rotation the Home spotlight uses (BrunoHomeViewModel resolveDaySeed).
    private var daySeed: UInt32 {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return UInt32(truncatingIfNeeded: (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0))
    }

    // Stable membership (top ≤20 recognizable studios present), order rotated by the day-seed.
    private var topStudios: [BaseItemDto] {
        var byName: [String: BaseItemDto] = [:]
        for item in items {
            guard let name = item.name else { continue }
            let key = Self.normalizeStudio(name)
            if byName[key] == nil { byName[key] = item }
        }
        let membership = Self.recognizableStudios
            .compactMap { byName[Self.normalizeStudio($0)] }
            .prefix(Self.topStudioLimit)
        return BrunoRNG.shuffled(Array(membership), seed: daySeed)
    }
}

// MARK: - NavigationRoute

extension NavigationRoute {

    @MainActor
    static func brunoStudiosGrid(
        title: String,
        items: [BaseItemDto]
    ) -> NavigationRoute {
        NavigationRoute(
            id: "bruno-studios-grid-\(title.lowercased())",
            withNamespace: { .push(.zoom(sourceID: "item", namespace: $0)) }
        ) {
            BrunoStudiosGridView(title: title, items: items)
        }
    }
}
