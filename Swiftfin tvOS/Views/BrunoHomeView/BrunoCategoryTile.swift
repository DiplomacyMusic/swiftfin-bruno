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

// MARK: - BrunoCuratedCard

//
// Name-keyed styling for the CURATED sub-collection cards (the ones reached by drilling into the
// Curated tile, rendered by BrunoCategoryTile). The owner's Ebert/Oscar imagery is already bundled —
// Curated01 = the Oscar statuette, Curated02 = the Roger Ebert photo — and reused here as a card
// background. This is a NAME contract (drift site, like `lens(for:)` / `labelArtStyle(for:)`): the
// match is anchored with `hasPrefix`, and the 8 top-level group names are disjoint from these, so it
// only fires for curated children. Genre cards never reach BrunoCategoryTile (the Genres tab renders
// its own label-art cells), so a genre like "Oscar Bait" can't collide.
enum BrunoCuratedCard {

    /// Bundled background asset for a curated card, by name. nil ⇒ no bundled art (use the
    /// collection's own representative poster — "a static movie cover that represents the meaning").
    static func assetName(for name: String) -> String? {
        let n = name.lowercased()
        if n.hasPrefix("oscar") { return "Curated01" } // Oscar statuette
        if n.hasPrefix("ebert") { return "Curated02" } // Roger Ebert photo
        return nil
    }

    /// Splits a curated card name into a small eyebrow + a big title. "Oscar — Cinematography" ⇒
    /// ("OSCAR", "Cinematography") so the card reads OSCAR small over the category big (owner request).
    /// Anything without the "Oscar — " form ⇒ (nil, name): a single centred title, unchanged.
    static func titleParts(_ name: String) -> (eyebrow: String?, title: String) {
        if name.lowercased().hasPrefix("oscar"), let r = name.range(of: " — ") {
            return (String(name[..<r.lowerBound]).uppercased(), String(name[r.upperBound...]))
        }
        return (nil, name)
    }

    /// Single-line display name with the em-dash removed (shelf headers / poster titles). "Oscar —
    /// Cinematography" ⇒ "Oscar Cinematography". A no-op for every name without the separator.
    static func display(_ name: String) -> String {
        name.replacingOccurrences(of: " — ", with: " ")
    }
}

// MARK: - BrunoCategoryTile

//
// The code-drawn artwork for a Collections category navigation tile. Replaces the per-group
// server poster images, which (a) baked the label into the bitmap — so "New Releases" rendered a
// giant "NEW" that we couldn't resize — and (b) left the synthetic "Boxed Sets" category with no
// image at all (the grey placeholder). A code tile draws every label at a CONTROLLED size over a
// per-category gradient + accent underline, matching the existing STUDIOS / SEASONAL banner look.
//
// Curated sub-collections (Oscar categories, Ebert Thumbs Up/Down, …) reach this same tile via the
// Curated drill-in, so they get the identical "selection card" treatment — with a per-card background
// (BrunoCuratedCard): Oscar → the Oscar statuette (pinned, no film-art cross-fade — the image is the
// point); Ebert → the Ebert photo (pinned); everything else → its own representative poster.
//
// Pure drawing: no `@FocusState`. The enclosing `Button(...).buttonStyle(.card)` owns focus
// scaling/lift; `posterStyle(.portrait)` gives the poster shape + aspect the card scales.
struct BrunoCategoryTile: View {

    let category: BrunoCollectionCategory

    var body: some View {
        let palette = Self.palette(for: category.name)
        Group {
            if category.name.lowercased() == "rewatchables" {
                // Self-titled brand art: the image already reads "THE REWATCHABLES", so no text
                // overlay. Plum gradient backstop behind the cover (shows only if it can't fill).
                ZStack {
                    LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom)
                    Color.clear
                        .overlay { Image("RewatchablesCard").resizable().scaledToFill() }
                        .clipped()
                }
            } else if let asset = BrunoCuratedCard.assetName(for: category.name) {
                // Oscar / Ebert curated card: a PINNED bundled photo (owner: the image is the point,
                // so no film-art cross-fade), title overlaid like the collection tiles.
                ZStack {
                    BrunoCuratedPinnedArt(asset: asset, palette: palette)
                    foreground(palette: palette)
                }
            } else {
                // On focus, dimmed film art from this category cross-fades behind the title; at rest
                // it's the branded gradient tile (top-level groups) or the collection's own poster
                // (curated "other" children — a representative cover). Portrait art to match the tile
                // shape; children are the fallback art source for synthetic categories (Boxed Sets).
                BrunoFocusArtCycle(
                    parentID: category.boxSet.id,
                    fallbackItems: category.children,
                    type: .portrait
                ) {
                    background(palette: palette)
                } foreground: {
                    foreground(palette: palette)
                }
            }
        }
        .posterStyle(.portrait)
    }

    /// At-rest background: the bundled category photo over the brand gradient (top-level groups,
    /// Seasonal date-gated), or — for a curated "other" sub-collection with no bundled mapping — its
    /// own representative poster, dimmed, so it reads as "a movie cover that represents the meaning".
    @ViewBuilder
    private func background(palette: (top: Color, bottom: Color, underline: Color)) -> some View {
        if BrunoCollectionArtwork.dailyAsset(for: category.name) != nil
            || BrunoCollectionArtwork.isSeasonal(category.name)
        {
            BrunoCollectionArtBackground(categoryName: category.name, palette: palette)
        } else {
            ZStack {
                LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom)
                PosterImage(item: category.boxSet, type: .portrait)
                    .overlay(Color.black.opacity(0.55)) // dim so the title reads over the cover
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
            }
        }
    }

    @ViewBuilder
    private func foreground(palette: (top: Color, bottom: Color, underline: Color)) -> some View {
        let (eyebrow, title) = BrunoCuratedCard.titleParts(category.name)
        VStack(spacing: eyebrow == nil ? 16 : 10) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.brunoBody(22, weight: .semibold))
                    .tracking(4)
                    .foregroundStyle(Color.bruno.accent)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
            }

            Text(title.uppercased())
                // Bigger base when there's an "OSCAR" eyebrow so the category fills the card edge to
                // edge; long ones (Cinematography) shrink via minimumScaleFactor, short ones stay big.
                    .font(.brunoDisplay(eyebrow == nil ? 38 : 46, weight: .bold))
                    .foregroundStyle(Color.bruno.fg)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    // Controlled sizing: long labels shrink to fit instead of overflowing the tile
                    // (the "giant NEW" fix), short ones still read large.
                    .minimumScaleFactor(0.4)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 2)

            Capsule()
                .fill(palette.underline)
                .frame(width: 64, height: 5)
        }
        .padding(.horizontal, 20)
    }

    /// Per-category hue, keyed case-insensitively by group name (unknown names fall back to the
    /// brand accent). Deep top → saturated bottom so white Oswald reads cleanly over it.
    private static func palette(for name: String) -> (top: Color, bottom: Color, underline: Color) {
        switch name.lowercased() {
        case "new releases":
            (Color(hex: "2A1606"), Color(hex: "C25A1E"), Color(hex: "F2802E"))
        case "genres":
            (Color(hex: "1A1026"), Color(hex: "6B3FB0"), Color(hex: "9E6BE0"))
        case "directors":
            (Color(hex: "08191E"), Color(hex: "2E6B7C"), Color(hex: "5BB6CC"))
        case "boxed sets":
            // Cobalt — distinct from the amber Decades tile it sits beside (and every other tile).
            (Color(hex: "0B1430"), Color(hex: "2A45A8"), Color(hex: "5C7CE6"))
        case "decades":
            (Color(hex: "201408"), Color(hex: "9C6A1E"), Color(hex: "E0902E"))
        case "curated":
            (Color(hex: "0C1C0E"), Color(hex: "356B36"), Color(hex: "5FB060"))
        case "studios":
            (Color(hex: "240A12"), Color(hex: "9C2336"), Color(hex: "E03A5A"))
        case "seasonal":
            (Color(hex: "06191E"), Color(hex: "1E7C8C"), Color(hex: "2EB6CC"))
        case "rewatchables":
            // Plum — distinct from every other tile (podcast/rewatch warmth).
            (Color(hex: "1E0C1A"), Color(hex: "7A2A5A"), Color(hex: "C04A8E"))
        default:
            (Color.bruno.diplomacyDark, Color.bruno.accentAlt, Color.bruno.accent)
        }
    }
}

// MARK: - BrunoCuratedPinnedArt

//
// A bundled photo pinned behind a curated card's title (no film-art cross-fade). Mirrors
// BrunoCollectionArtImage's layout idiom: Color.clear drives the (poster-shaped) layout and the
// photo paints as a zero-layout-influence, clipped overlay, so it can never grow the card past its
// `.posterStyle(.portrait)` frame (the documented overgrowth bug). Brand gradient base as a backstop.
private struct BrunoCuratedPinnedArt: View {

    let asset: String
    let palette: (top: Color, bottom: Color, underline: Color)

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom)

            Color.clear
                .overlay {
                    Image(asset)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .overlay(Color.black.opacity(0.5)) // lighter than the tile photos: the statue/face is the point

            // Legibility wash where the centred title sits.
            LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .center, endPoint: .bottom)
        }
    }
}
