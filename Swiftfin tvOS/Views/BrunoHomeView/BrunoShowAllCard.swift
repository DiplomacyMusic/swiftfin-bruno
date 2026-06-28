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

// MARK: - BrunoShowAllCard

//
// The trailing "Show all" card for Home shelves (D1 — "two doors to the same end room"). Mirrors
// BrunoShelfRow's browse-surface card but is poster-TYPE aware (landscape AND portrait), so a Home
// landscape shelf's card self-sizes to the same height as its landscape posters and the row keeps
// its BrunoShelfMetrics height pin (INV-1). It is always present per shelf and holds no per-item
// state beyond its own focus ring — a single constant-id sentinel that never recycles onto a poster
// (INV-10).
struct BrunoShowAllCard: View {

    let type: PosterDisplayType
    /// nil ⇒ the generic "Show all"; otherwise "Show all · <title>" (mirrors BrunoShelfRow).
    var title: String?
    let action: () -> Void

    @FocusState
    private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.bruno.fg.opacity(isFocused ? 0.2 : 0.12))

                    // Accent focus ring (matches BrunoSelectorCard / the hero pills) so the card
                    // reads as a deliberate branded affordance, not an inert grey placeholder.
                    if isFocused {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.bruno.accent, lineWidth: 3)
                    }

                    VStack(spacing: 10) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 44, weight: .semibold))
                        Text(title.map { "Show all · \($0)" } ?? "Show all")
                            .font(.brunoBody(22, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 8)
                    }
                    .foregroundStyle(Color.bruno.accent)
                }
                // Match the poster cell's art aspect for this type so the cell self-sizes correctly.
                .posterAspectRatio(type, contentMode: .fit)

                // Matches the poster cards' two-line title area so the row stays aligned (INV-1).
                Text(" ")
                    .font(.footnote)
                    .lineLimit(2, reservesSpace: true)
            }
        }
        .buttonStyle(.card)
        .focused($isFocused)
        // Debug HUD: a discrete nav-input marker when the trailing card takes focus (inert unless a
        // debug overlay is on). See Shared/Objects/Bruno/BrunoDebugInstrument.swift.
        .brunoDebugNavFocus("show-all", isFocused: isFocused)
    }
}

// swiftlint:enable hard_coded_display_string
