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

// MARK: - BrunoCollectionsView (tvOS only)

//
// The Collections tab, redesigned from a flat BoxSet grid into per-category shelves (roadmap §3):
// a category row across the top, then one capped shelf per curated group (Directors, Decades,
// Studios, …). Genres/Decades "Show all" drills into a further shelf-per-sub-group view (§4);
// the rest open the stock full grid. Rendering is delegated to the shared BrunoCategoryShelves.
struct BrunoCollectionsView: View {

    @StateObject
    private var viewModel = BrunoCollectionsViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(2)
                    .tint(Color.bruno.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.categories.isEmpty {
                emptyState
            } else {
                BrunoCategoryShelves(
                    categories: viewModel.categories,
                    eyebrow: "Browse the Library",
                    featured: brunoFeaturedItem(in: viewModel.categories),
                    heroEyebrow: "Featured",
                    // Collections TAB ROOT → inject the scrolling menu bar as the first row.
                    isTabRoot: true,
                    // Back the unfocused Decades cards with each decade's best-of film cover.
                    decadeBestOf: viewModel.decadeBestOf,
                    // The ≥24-shelf procedural tail below the static groups, + the snapshot for its
                    // Show-all routing.
                    tailShelves: viewModel.tailShelves,
                    snapshot: viewModel.snapshot
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onFirstAppear {
            Task { await viewModel.load() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No collections yet")
                .font(.brunoDisplay(40, weight: .semibold))
                .foregroundStyle(Color.bruno.fg)
            Text("Curated collections from this server will appear here.")
                .font(.brunoBody(22))
                .foregroundStyle(Color.bruno.fgMuted)
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - BrunoCollectionsViewModel

@MainActor
final class BrunoCollectionsViewModel: ViewModel {

    @Published
    private(set) var categories: [BrunoCollectionCategory] = []
    @Published
    private(set) var isLoading = true
    /// Decade-name → best-of-decade film cover, lifted from the shared snapshot so the Decades shelf can
    /// back each unfocused decade card with the film cover (same data the Home Eras cards use). nil for
    /// pre-feature on-disk payloads ⇒ gradient fallback.
    @Published
    private(set) var decadeBestOf: [String: BaseItemDto]?
    /// The procedural tail (≥24 Home-style shelves) appended below the static group shelves. Realized
    /// AFTER the static surface is interactive, then published in one shot (thin rows filtered out).
    @Published
    private(set) var tailShelves: [BrunoShelfViewModel] = []
    /// The loaded snapshot, exposed so the view can thread it into the tail's Show-all routing.
    @Published
    private(set) var snapshot: BrunoLibrarySnapshot = .empty

    /// Per-launch seed for the procedural tail: stable within a process (re-entering Collections keeps
    /// the same lineup), reshuffles on the next app launch — the owner's "seed-keyed, reshuffles per
    /// launch" choice. A browse surface, inside the documented INV-3 carve-out.
    private static let tailSeed: UInt32 = .random(in: .min ... .max)

    func load() async {
        guard let userSession else {
            isLoading = false
            return
        }

        let client = userSession.client
        let userID = userSession.user.id
        // Reuse the snapshot Home just loaded (shared cache) instead of refetching the whole
        // library on every Home -> Collections navigation.
        let snapshot = await BrunoLibrarySnapshot.loadShared(client: client, userID: userID)

        // The full group-tile set (Directors, Decades, …, plus the synthetic Boxed Sets), built and
        // rank-ordered from the shared snapshot. `fromSnapshot` now surfaces Boxed Sets from the
        // snapshot's cached `franchiseBoxSets`, so the Collections hub, the Home footer, and the Home
        // "Browse the Collection" shelf are byte-identical (same cards, same order, same destinations).
        categories = BrunoCollectionCategory.fromSnapshot(snapshot)
        decadeBestOf = snapshot.decadeBestOf
        self.snapshot = snapshot
        // Static surface is interactive now; the tail loads below the fold.
        isLoading = false

        // Procedural tail: realize the ≥24 seeded descriptors into paging VMs, load them concurrently,
        // and publish the ones with enough items to read as a row. The cap-and-grow mount window in
        // BrunoCategoryShelves (INV-8) gates how many actually render, so realizing all the VMs here is
        // a fetch cost (off the main thread), not a render-burst cost.
        let descriptors = BrunoHomePlan.collectionsTail(seed: Self.tailSeed, snapshot: snapshot)
        let vms = descriptors.map { BrunoShelfViewModel(shelf: $0) }
        await withTaskGroup(of: Void.self) { group in
            for vm in vms {
                group.addTask { await vm.load() }
            }
        }
        tailShelves = vms.filter(\.shouldDisplay)
    }
}
