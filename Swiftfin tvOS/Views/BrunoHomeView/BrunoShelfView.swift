//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import JellyfinAPI
import SwiftUI

// MARK: - BrunoShelfView

//
// One horizontal carousel: a Bruno-styled header (accent eyebrow + Oswald title) over the
// stock tvOS `PosterHStack`, which gives native focus, scaling and the card → stock detail
// route for free (plan §C1/§C4). Guarded on `isNotEmpty` like `LatestInLibraryView`.
struct BrunoShelfView: View {

    @ObservedObject
    var viewModel: BrunoShelfViewModel

    /// The library snapshot (from BrunoHomeView) so each shelf's trailing "Show all" can resolve its
    /// browse destination (D1) and the Eras tiles can deep-link to the Decades pill (D2). Defaults to
    /// empty for previews / non-Home callers — their "Show all" simply no-ops.
    var snapshot: BrunoLibrarySnapshot = .empty

    @Router
    private var router

    // Mirrors BrunoCategoryCardRow: a namespace for the zoom transition into the "Show all" grid.
    @Namespace
    private var namespace

    // The custom tab container keeps hidden tabs mounted (so they never fire onDisappear). When this
    // shelf's tab deactivates, free its warmed poster set instead of letting it linger in memory.
    @Environment(\.brunoTabIsActive)
    private var isActiveTab

    // INV-4: warms this row's posters into the same pipeline at the same width the cells request,
    // so a freshly-revealed or horizontally-scrolled row isn't blank. Cancelled on disappear.
    @State
    private var prefetcher = BrunoPosterPrefetcher()

    var body: some View {
        if viewModel.items.isNotEmpty {
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(viewModel.lens.uppercased())
                        .font(.brunoBody(20, weight: .semibold))
                        .tracking(3)
                        .foregroundStyle(Color.bruno.accent)

                    Text(viewModel.title)
                        .font(.brunoDisplay(36, weight: .semibold))
                        .foregroundStyle(Color.bruno.fg)
                }
                .padding(.horizontal, 50)
                // Portrait shelves only: keep the focus-scaled leading cell from growing up into this
                // header (see BrunoShelfMetrics.portraitHeaderBottomInset).
                .padding(.bottom, viewModel.posterType == .portrait ? BrunoShelfMetrics.portraitHeaderBottomInset : 0)

                // Just Added (the .recentlyAdded spine shelf) shows the full release date in the
                // poster subtitle line — movies' item.subtitle is nil there, so BrunoTitleDateContentView
                // fills the already-reserved blank line (INV-1 row height unchanged). Every other shelf
                // omits the label argument and renders PosterHStack's default TitleSubtitleContentView
                // byte-identically.
                // INV-1: Pin EVERY shelf (portrait AND landscape) so the LazyVStack stops re-reading
                // CollectionHStack's intrinsic height on vertical focus moves — that renegotiation is
                // the up/down "math conflict" that hard-snaps the row with no intervening frames. It
                // also keeps the spine geometry constant while shelves stream in. Both heights are the
                // single source of truth in BrunoShelfMetrics (see docs/BRUNO_PERF_INVARIANTS.md). The
                // pinned height is identical in both branches — the only difference is the Just Added
                // poster label — so the row geometry is unchanged.
                // Every shelf gets a trailing "Show all" card (D1) via posterRow / carouselRow. The
                // recentlyAdded branch keeps its release-date poster label; portrait uses the Bruno
                // two-line title; landscape uses the shared default — all with identical reserved
                // label height, so INV-1's pinned row geometry is unchanged.
                if viewModel.shelf.kind == .recentlyAdded {
                    posterRow(site: "shelf:recentlyAdded") { BrunoTitleDateContentView(item: $0) }
                } else if viewModel.items.first?.type == .boxSet {
                    // Collection shelves (Studios / Directors / Eras / Boxed Sets, …): focus-cycling
                    // carousel cards. Same card geometry as PosterButton, so INV-1's row height holds.
                    carouselRow
                        .frame(height: BrunoShelfMetrics.shelfRowHeight(for: viewModel.posterType))
                        .brunoPerfHeightWatch(site: "shelf:carousel", expected: BrunoShelfMetrics.shelfRowHeight(for: viewModel.posterType))
                } else if viewModel.posterType == .portrait {
                    posterRow(site: "shelf:portrait") { BrunoPosterTitleContentView(item: $0) }
                } else {
                    posterRow(site: "shelf:landscape") { PosterButton<BaseItemDto>.TitleSubtitleContentView(item: $0) }
                }
            }
            .onAppear {
                prefetcher.warm(viewModel.items.elements, type: viewModel.posterType)
            }
            .onDisappear {
                prefetcher.stop(viewModel.items.elements, type: viewModel.posterType)
            }
            .onChange(of: isActiveTab) { _, active in
                // Tab hidden → cancel prefetch (no onDisappear fires for an opacity-hidden tab); tab
                // shown again → re-warm the still-mounted row.
                if active {
                    prefetcher.warm(viewModel.items.elements, type: viewModel.posterType)
                } else {
                    prefetcher.stop(viewModel.items.elements, type: viewModel.posterType)
                }
            }
            // Debug HUD instrumentation (inert unless a debug overlay is on): count shelf redraws
            // and track the shelf's vertical movement — the up/down "graphic math" the perf
            // invariants fight. See Shared/Objects/Bruno/BrunoDebugInstrument.swift.
            .brunoDebugRedraw("shelf:\(viewModel.title)")
            .brunoDebugLayout("shelf:\(viewModel.title)")
        }
    }

    // MARK: - Show all (D1) + tap routing

    /// A standard poster shelf with a trailing "Show all" card. Folds the shared PosterHStack's
    /// (now opt-in) trailing slot in for every Home shelf, pinned to BrunoShelfMetrics (INV-1).
    @ViewBuilder
    private func posterRow(site: String, @ViewBuilder label: @escaping (BaseItemDto) -> any View) -> some View {
        let height = BrunoShelfMetrics.shelfRowHeight(for: viewModel.posterType)
        PosterHStack(
            title: nil,
            type: viewModel.posterType,
            items: viewModel.items,
            action: { handleTap($0) },
            label: label
        )
        .trailing { BrunoShowAllCard(type: viewModel.posterType, action: showAll) }
        .frame(height: height)
        // INV-1 conflict watch (perf telemetry, release-inert). See BrunoShelfRow / BrunoDebugInstrument.
        .brunoPerfHeightWatch(site: site, expected: height)
    }

    /// D1: route this shelf's "Show all" to the SAME destination as its browse twin.
    private func showAll() {
        brunoHomeRouteToShowAll(shelf: viewModel.shelf, snapshot: snapshot, router: router, namespace: namespace)
    }

    /// Default poster/tile tap → item detail; D2: an Eras decade tile deep-links into the Decades
    /// surface with that decade's pill pre-selected.
    private func handleTap(_ item: BaseItemDto) {
        if viewModel.shelf.kind == .eras,
           let decadesGroup = snapshot.favoriteGroupBoxSets.first(where: { $0.displayTitle.lowercased() == "decades" })
        {
            router.route(to: .brunoCategoryShelves(parent: decadesGroup, decade: item.displayTitle), in: namespace)
        } else {
            router.route(to: .item(item: item))
        }
    }

    // MARK: - Carousel (collection shelves)

    /// A poster cell or the trailing "Show all" sentinel for the carousel row. Constant-id sentinel
    /// (INV-10: always present, never recycles onto a collection card).
    private enum CarouselCard: Identifiable, Hashable {
        case item(BaseItemDto)
        case showAll

        var id: CarouselCard {
            self
        }
    }

    private var carouselCards: [CarouselCard] {
        Array(viewModel.items.prefix(20)).map(CarouselCard.item) + [.showAll]
    }

    /// Mirrors PosterHStack's CollectionHStack layout exactly (same columns / insets / spacing /
    /// scroll behaviour, so the row matches every other shelf), but draws BrunoArtCarouselCard so a
    /// focused collection card cycles its films behind the static art — plus the trailing Show-all card.
    private var carouselRow: some View {
        CollectionHStack(
            uniqueElements: carouselCards,
            columns: viewModel.posterType == .landscape ? 4 : 7
        ) { card in
            switch card {
            case let .item(item):
                BrunoArtCarouselCard(item: item, type: viewModel.posterType) {
                    handleTap(item)
                } label: {
                    PosterButton<BaseItemDto>.TitleSubtitleContentView(item: item)
                }
            case .showAll:
                BrunoShowAllCard(type: viewModel.posterType, action: showAll)
            }
        }
        .clipsToBounds(false)
        .dataPrefix(carouselCards.count)
        .insets(horizontal: EdgeInsets.edgePadding, vertical: 20)
        .itemSpacing(EdgeInsets.edgePadding - 20)
        .scrollBehavior(.continuousLeadingEdge)
        .focusSection()
    }
}
