//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import SwiftUI

// TODO: trailing content refactor?

struct PosterHStack<Element: Poster, Data: Collection>: View where Data.Element == Element, Data.Index == Int {

    private var data: Data
    private var title: String?
    private var type: PosterDisplayType
    private var label: (Element) -> any View
    private var trailingCard: (() -> any View)?
    private let action: (Element) -> Void

    // A poster cell or the trailing "Show all" sentinel. The sentinel is appended ONLY when a
    // trailing card is provided (Bruno Home shelves, via `.trailing { … }`); stock callers leave
    // `trailingCard` nil and never build it, so their render path is byte-identical to before.
    private enum Card: Identifiable, Hashable {
        case item(Element)
        case showAll

        var id: Card {
            self
        }
    }

    // The capped poster set (the existing dataPrefix(20) behaviour) plus the trailing card as the
    // last element, so "Show all" sits at the end of the row exactly like the browse surfaces.
    private var trailingCards: [Card] {
        Array(data.prefix(20)).map(Card.item) + [.showAll]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            if let title {
                HStack {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .accessibility(addTraits: [.isHeader])
                        .padding(.leading, 50)

                    Spacer()
                }
            }

            if let trailingCard {
                // Opt-in path (Bruno Home shelves): the capped posters + a trailing "Show all"
                // card as the final, constant-id sentinel element (INV-10: structurally stable —
                // its presence is fixed for the shelf, never toggled on focus/state).
                CollectionHStack(
                    uniqueElements: trailingCards,
                    columns: type == .landscape ? 4 : 7
                ) { card in
                    switch card {
                    case let .item(item):
                        PosterButton(
                            item: item,
                            type: type
                        ) {
                            action(item)
                        } label: {
                            label(item).eraseToAnyView()
                        }
                    case .showAll:
                        trailingCard().eraseToAnyView()
                    }
                }
                .clipsToBounds(false)
                .dataPrefix(trailingCards.count)
                .insets(horizontal: EdgeInsets.edgePadding, vertical: 20)
                .itemSpacing(EdgeInsets.edgePadding - 20)
                .scrollBehavior(.continuousLeadingEdge)
            } else {
                CollectionHStack(
                    uniqueElements: data,
                    columns: type == .landscape ? 4 : 7
                ) { item in
                    PosterButton(
                        item: item,
                        type: type
                    ) {
                        action(item)
                    } label: {
                        label(item).eraseToAnyView()
                    }
                }
                .clipsToBounds(false)
                .dataPrefix(20)
                .insets(horizontal: EdgeInsets.edgePadding, vertical: 20)
                .itemSpacing(EdgeInsets.edgePadding - 20)
                .scrollBehavior(.continuousLeadingEdge)
            }
        }
        .focusSection()
    }
}

extension PosterHStack {

    init(
        title: String? = nil,
        type: PosterDisplayType,
        items: Data,
        action: @escaping (Element) -> Void,
        @ViewBuilder label: @escaping (Element) -> any View = { PosterButton<Element>.TitleSubtitleContentView(item: $0) }
    ) {
        self.init(
            data: items,
            title: title,
            type: type,
            label: label,
            trailingCard: nil,
            action: action
        )
    }

    func trailing(@ViewBuilder _ content: @escaping () -> any View) -> Self {
        copy(modifying: \.trailingCard, with: content)
    }
}
