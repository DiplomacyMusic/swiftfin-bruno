//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// MARK: - BrunoFocusArtCycle (tvOS only)

//
// Reusable focus treatment: a card/tile that, WHILE FOCUSED, cross-fades DIMMED artwork (a random
// sample of films under `parentID`, or `fallbackItems` for synthetic categories) BEHIND a fully
// static foreground (title, logo, …); at rest it shows just `background`. Drop on any focusable
// surface — the group tiles here, and other systems later.
//
// Design rules (from owner feedback):
//   • Art is type-matched to the CARD shape (`type`) and constrained to the card frame — a portrait
//     tile cycles portrait art and never bleeds into a landscape rectangle.
//   • The foreground is STATIC — only the art layer animates. No `.animation` touches the title.
//   • Frame-to-frame is a true two-layer cross-dissolve (new frame opaque underneath, old fades out
//     on top), so there's no dip to black between frames.
//
// Perf-safe by construction: reads `\.isFocused` so ONLY the focused card cycles; a brief hold before
// the first frame; frames prefetched into the Nuke memory cache (BrunoPosterPrefetcher, same pipeline
// + width as the cells) so swaps never gap; cycle task cancelled on unfocus/disappear; Reduce Motion
// holds the static background.
//
// STRUCTURAL STABILITY (held-scroll regression fix — supersedes the focus-gated-INSERTION design).
// The focused cell's view-tree STRUCTURE must NOT change when `\.isFocused` flips. A previous
// version inserted the heavy art subtree only `if isFocused { ArtCycleOverlay(…) }`, so gaining
// focus added a child node to the focused cell's subtree DURING its own focus update. On tvOS that
// invalidates the self-sizing UICollectionView cell mid-focus-pass and can make the focus engine
// reset-in-place instead of advancing: pressing-and-HOLDING the remote to scroll then stalled after
// ~3 rows (you had to lift and re-press). The bridged `CollectionHStack` (UICollectionView) nesting
// amplifies it. So: the art subtree is ALWAYS present in the ZStack; node identity + layout stay
// constant across focus updates. We gate WORK (load/cycle/prefetch) and VISIBILITY on focus, never
// the tree's shape.
//
// This costs us one always-present `@StateObject BrunoArtCycleViewModel` per cell (it allocates a
// BrunoPosterPrefetcher). That is acceptable and is NOT the thing we trade for held-scroll: the heavy
// part — the GetItems request, the frame prefetch, the cycling Task — still runs ONLY while focused
// (driven by `.onChange(of: isFocused)` / `.onDisappear`), and an unfocused cell renders only
// `background()` + `foreground()` (the art layer is present but draws nothing, `active == false`).
//
// REUSE-SAFE (INV-10). `CollectionHStack` now REUSES the cell's UIHostingController and swaps its
// `rootView` on recycle, so a recycled cell's `@StateObject`/`@State` can survive into a DIFFERENT
// item. Two guards prevent ever flashing the previous item's art: (1) `active` is gated on focus, and
// recycled cells are offscreen/unfocused → the art layer is invisible the instant the cell is reused;
// (2) the load is parentID-aware (`BrunoArtCycleViewModel.load` resets+reloads when the load key
// changes), so even if a stale VM survives, its frames are cleared before the new item's art arrives.
struct BrunoFocusArtCycle<Background: View, Foreground: View>: View {

    private let parentID: String?
    private let fallbackItems: [BaseItemDto]
    private let type: PosterDisplayType
    private let dim: Double
    private let background: () -> Background
    private let foreground: () -> Foreground

    init(
        parentID: String?,
        fallbackItems: [BaseItemDto] = [],
        type: PosterDisplayType = .portrait,
        dim: Double = 0.55,
        @ViewBuilder background: @escaping () -> Background,
        @ViewBuilder foreground: @escaping () -> Foreground
    ) {
        self.parentID = parentID
        self.fallbackItems = fallbackItems
        self.type = type
        self.dim = dim
        self.background = background
        self.foreground = foreground
    }

    @Environment(\.isFocused)
    private var isFocused
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    // Always present — see the type comment. SwiftUI builds this `@StateObject`'s initial value for
    // every cell as the graph is built (focused or not), which is the price of structural stability.
    // The heavy work it owns is still focus-gated below, so an unfocused cell pays only the (cheap)
    // allocation, never a GetItems/prefetch.
    @StateObject
    private var art = BrunoArtCycleViewModel()
    @State
    private var index = 0
    /// The outgoing frame's index, rendered on TOP of the (opaque) current frame and faded to 0 — the
    /// seamless dissolve: the new frame is already fully painted underneath, so nothing dips to black.
    @State
    private var fadingIndex: Int?
    @State
    private var fadeOpacity: Double = 0
    @State
    private var rolling = false
    @State
    private var cycle: Task<Void, Never>?

    private static var holdSeconds: Double {
        1.5
    }

    private static var frameSeconds: Double {
        1.25
    }

    private static var dissolveSeconds: Double {
        0.55
    }

    // VISIBILITY gate (not a structural gate). False at rest and the instant focus is lost, so an
    // unfocused/recycled cell shows only background + foreground — pixel-identical to a card with no
    // art cycle. Also false until the CURRENT item's frames load, so reuse can never flash stale art.
    private var active: Bool {
        rolling && !art.frames.isEmpty
    }

    var body: some View {
        ZStack {
            background()

            // Art layer — the ONLY animated part. ALWAYS in the tree (structural stability), but draws
            // nothing until `active` (focused + this item's frames loaded), so at rest it's a no-op.
            // Visibility is gated here; the subtree's existence/identity is NOT — the ZStack's child
            // shape is constant across focus updates, which is what keeps held-scroll advancing.
            artLayer

            foreground() // STATIC — no animation reaches it
        }
        .clipped()
        // WORK is focus-gated here (not by conditional view presence): gaining focus loads this item's
        // art (parentID-aware) and starts the cycle; losing focus cancels the Task + prefetch. On
        // focus we also reset the cross-fade `@State` so a recycled VM/cell never resumes mid-dissolve
        // for the wrong item.
        .onChange(of: isFocused) { _, focused in
            if focused {
                index = 0
                fadingIndex = nil
                fadeOpacity = 0
                rolling = false
                art.load(parentID: parentID, fallbackItems: fallbackItems, type: type)
                start()
            } else {
                stop()
            }
        }
        .onDisappear(perform: stop)
    }

    // The two-layer cross-dissolve. Wrapped so the art's ON/OFF is opacity-only (`if active`), leaving
    // the layer permanently in the ZStack: when inactive it resolves to an empty `Group` that occupies
    // the slot without adding/removing a structural node on focus.
    @ViewBuilder
    private var artLayer: some View {
        // Fades in over the gradient once active; renders nothing until the first frame rolls so the
        // hold reads exactly as before — the rest background shows untouched during the hold.
        Group {
            if active {
                ZStack {
                    if let current = art.frames[safe: index] {
                        frame(current, key: index) // current frame, opaque, underneath
                    }
                    if let fadingIndex, let fading = art.frames[safe: fadingIndex] {
                        frame(fading, key: fadingIndex).opacity(fadeOpacity) // previous frame, fading out on top
                    }
                }
                .transition(.opacity)
            }
        }
    }

    // `key` forces a fresh ImageView identity per frame: ImageView holds its sources in @State, so
    // without a changing id it would freeze on the first image.
    private func frame(_ source: [ImageSource], key: Int) -> some View {
        // Color.clear drives layout (flexible, zero ideal size); the art paints as a zero-layout-
        // influence overlay. Sizing the view FROM the image instead (aspectRatio.fill + maxWidth/
        // maxHeight) let each frame's intrinsic ratio govern height inside this ZStack, so the card
        // grew/shifted as frames cross-faded — worst in the un-pinned category row ("position movement
        // on the first BG cycle"). As an overlay the art never changes the card's poster-shaped size.
        Color.clear
            .overlay {
                ImageView(source)
                    .scaledToFill()
            }
            .clipped()
            .overlay(Color.black.opacity(dim)) // dim so the foreground stays legible
            .id(key)
    }

    private func start() {
        stop()
        guard !reduceMotion else { return }
        cycle = Task { @MainActor in
            // Hold: show the tile as-is briefly so a quick focus pass doesn't flash.
            try? await Task.sleep(for: .seconds(Self.holdSeconds))
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.4)) { rolling = true }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.frameSeconds))
                if Task.isCancelled { return }
                let count = art.frames.count
                guard count > 1 else { continue }

                // Paint the new frame underneath (instant), cover it with the old frame on top, then
                // fade the old out → seamless dissolve, no black between.
                fadingIndex = index
                index = (index + 1) % count
                fadeOpacity = 1
                try? await Task.sleep(for: .milliseconds(20))
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: Self.dissolveSeconds)) { fadeOpacity = 0 }
            }
        }
    }

    private func stop() {
        cycle?.cancel()
        cycle = nil
        rolling = false
        fadingIndex = nil
        fadeOpacity = 0
        art.stopPrefetch()
    }
}

// MARK: - BrunoArtCycleViewModel

//
// Loads a random sample of film art (cached per load key) and prefetches every frame so the cycle
// never gaps. Art is type-matched to the card: portrait posters for portrait tiles, landscape
// (Thumb/Backdrop) for landscape. Uses `fallbackItems` directly when `parentID` resolves to nothing
// (synthetic categories like Boxed Sets, whose group BoxSet has no real id).
//
// REUSE-SAFE LOAD (INV-10). `CollectionHStack` reuses the cell's hosting controller and swaps its
// `rootView`, so this VM (`@StateObject` on the always-present BrunoFocusArtCycle) can survive into a
// DIFFERENT item. A one-shot `guard !loaded` would then keep painting the PREVIOUS item's frames. So
// `load` is keyed: it derives a `loadKey` from the parentID AND the fallback items (synthetic
// categories share an empty parentID, so the fallbacks disambiguate them). On a key change it CLEARS
// `frames` immediately (no stale-art flash — the view's `active` gate hides the layer until the new
// item's frames arrive) and reloads for the new item. Same key ⇒ no-op (still load-once per item).
@MainActor
final class BrunoArtCycleViewModel: ViewModel {

    @Published
    private(set) var frames: [[ImageSource]] = []

    private let prefetcher = BrunoPosterPrefetcher()
    private var warmed: [BaseItemDto] = []
    private var warmedType: PosterDisplayType = .portrait
    /// The identity of the currently-loaded art set. nil ⇒ nothing loaded yet. When `load` is called
    /// with a different key (the cell was reused for a new item), we reset and reload for that key.
    private var loadedKey: String?

    func load(parentID: String?, fallbackItems: [BaseItemDto], type: PosterDisplayType) {
        guard let userSession else { return }
        // INV-10: parentID-aware (key-aware) reload is the reuse-safety guard. A recycled cell may
        // carry this VM into a new item; a different key resets+reloads so we never paint stale art.
        let key = Self.loadKey(parentID: parentID, fallbackItems: fallbackItems)
        // Same item we already loaded (a re-focus on the same cell) → keep the warm frames, no reload.
        guard key != loadedKey else { return }

        // Different item (cell reused, or first load). Drop the previous item's frames + prefetch
        // BEFORE the new request lands so the art layer can never flash the wrong item's art — the
        // view's `active` gate then keeps the layer hidden until the new frames arrive.
        if loadedKey != nil {
            prefetcher.stop(warmed, type: warmedType)
            warmed = []
            frames = []
        }
        loadedKey = key
        warmedType = type
        let client = userSession.client
        let userID = userSession.user.id
        let width = BrunoShelfMetrics.posterMaxWidth(for: type)
        let quality = BrunoShelfMetrics.posterQuality
        Task {
            var items: [BaseItemDto] = []
            if let parentID, !parentID.isEmpty {
                var parameters = Paths.GetItemsParameters()
                parameters.userID = userID
                parameters.parentID = parentID
                parameters.includeItemTypes = [.movie]
                parameters.isRecursive = true
                parameters.sortBy = [ItemSortBy.random]
                parameters.limit = 10
                items = await (try? client.send(Paths.getItems(parameters: parameters)).value.items) ?? []
            }
            if items.isEmpty {
                items = Array(fallbackItems.shuffled().prefix(10))
            }
            // The cell may have been reused for yet another item while this request was in flight —
            // bail if the key moved on, so we don't paint frames for a stale request.
            guard key == loadedKey else { return }
            let usable = items.filter { item in
                sources(for: item, type: type, width: width, quality: quality).contains { $0.url != nil }
            }
            warmed = usable
            frames = usable.map { sources(for: $0, type: type, width: width, quality: quality) }
            prefetcher.warm(usable, type: type)
        }
    }

    func stopPrefetch() {
        prefetcher.stop(warmed, type: warmedType)
    }

    /// Identity of an art set. parentID alone is not enough: synthetic categories (Boxed Sets) have no
    /// parent BoxSet id, so they'd all collapse to the empty key and a reused cell could keep one
    /// synthetic category's art for another. Fold the fallback item ids in to disambiguate them.
    private static func loadKey(parentID: String?, fallbackItems: [BaseItemDto]) -> String {
        if let parentID, !parentID.isEmpty { return parentID }
        return "fallback:" + fallbackItems.compactMap(\.id).joined(separator: ",")
    }

    private func sources(
        for item: BaseItemDto,
        type: PosterDisplayType,
        width: CGFloat,
        quality: Int
    ) -> [ImageSource] {
        type == .landscape
            ? item.landscapeImageSources(maxWidth: width, quality: quality)
            : item.portraitImageSources(maxWidth: width, quality: quality)
    }
}
