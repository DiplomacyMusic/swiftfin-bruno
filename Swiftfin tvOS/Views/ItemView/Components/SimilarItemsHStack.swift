//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Factory
import JellyfinAPI
import SwiftUI

extension ItemView {

    struct SimilarItemsHStack: View {

        @Default(.Customization.similarPosterType)
        private var similarPosterType

        @Router
        private var router

        // Bruno: Jellyfin's similar-items result leaks Bruno's nav-hub BoxSets into "Recommended" and
        // routes every BoxSet tile to the stock collection grid. We classify each tile against the warm
        // library snapshot to drop the hubs and reroute genuine collections to their branded Bruno
        // destinations, leaving movie/series tiles untouched. The shelf stays one homogeneous
        // PosterHStack (INV-1/-10): only the displayed items and the tap target change. See
        // BrunoRecommendedShelf.swift.
        @Namespace
        private var namespace

        @State
        private var snapshot: BrunoLibrarySnapshot = .empty

        let items: [BaseItemDto]

        init(items: [BaseItemDto]) {
            self.items = items
        }

        var body: some View {
            // Filtered against the snapshot: only recognized nav hubs fall out; every other tile is kept
            // (unrecognized BoxSets fail open to the stock item route — see BrunoRecommendedShelf), so the
            // shelf is never emptier than the raw similar-items list.
            let display = brunoRecommendedDisplayItems(items, snapshot: snapshot)

            Group {
                if display.isNotEmpty {
                    PosterHStack(
                        title: L10n.recommended,
                        type: similarPosterType,
                        items: display
                    ) { item in
                        routeBrunoRecommended(item, snapshot: snapshot, router: router, namespace: namespace)
                    }
                }
            }
            // Attach to the Group, not the PosterHStack: a similar list that is all BoxSets renders no
            // PosterHStack on the first pass, so the load must not depend on it being shown.
            .task {
                guard let session = Container.shared.currentUserSession() else { return }
                snapshot = await BrunoLibrarySnapshot.loadShared(client: session.client, userID: session.user.id)
            }
        }
    }
}
