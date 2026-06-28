//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI
import UIKit

// Prototype copy is English-only; localization (L10n) is a deferred TODO (see BRUNO_NOTES.md).
// swiftlint:disable hard_coded_display_string

// MARK: - BrunoHeroView

//
// The rotating spotlight: a seeded 5-item feature (the seed pool comes from the view model,
// plan §D). Full-bleed backdrop + left scrim, Oswald title, meta, and a Play / More-Info hint
// that routes to the stock item detail (Play-for-the-proto, plan §C4).
//
// Focus model (Apple-TV-app feel): the chrome-less hero shows focus through its own affordances
// (the brightened Play pill), not a card highlight. A MULTI-item spotlight makes the page dots a
// focusable `.focusSection()` row — LEFT/RIGHT pages the spotlight (move-to-select); UP/DOWN escape
// to the focus engine (menu bar above, shelves below) with NO `.onMoveCommand` sink (that trapped
// UP). Select on a dot opens the spotlight item. A SINGLE-item hero keeps the whole card as one
// focusable Button so a call site's external `.focused(...)` still binds.
// Auto-advance pauses while a dot is focused so the backdrop never swaps focus out from under you.
struct BrunoHeroView: View {

    let items: [BaseItemDto]

    /// Bound so the home's ambient backdrop can track the selected spotlight.
    @Binding
    var index: Int

    /// Eyebrow above the title. "Spotlight" on Home; browse surfaces pass their own ("Featured", …).
    var eyebrow: String = "Spotlight"

    /// The hero is the first scroll row, so bleed the backdrop up under the floating tab bar.
    var bleedsTop: Bool = false

    /// Grow the banner taller (and its bottom edge lower) by this much. A taller banner crops less of
    /// the 16:9 backdrop, so MORE of the source — including its top — survives, and the subject reads
    /// centered below the nav. Home also uses it to restore the space the wordmark row vacated.
    var extraHeight: CGFloat = 0

    /// The host LazyVStack's row spacing (the menu-bar↔hero gap). The top-bleed must clear exactly
    /// this gap to reach the physical top. Defaults to 36 (Kids/Movies/TV); Home passes 24.
    var rowSpacing: CGFloat = 36

    /// INV-8: while the home spine is still streaming in, hold the spotlight auto-advance so a
    /// backdrop swap never competes with shelves rising into place (two motion events at once reads
    /// as "busy/loading", not cinematic). The page passes `state == .content` once it has settled.
    var autoAdvanceEnabled: Bool = true

    @Router
    private var router

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @FocusState
    private var isFocused: Bool

    /// Which spotlight dot holds focus (multi-item hero); nil ⇒ none. Drives move-to-select paging
    /// and the auto-advance pause. Single-item heroes use `isFocused` (the whole-card Button) instead.
    @FocusState
    private var focusedDot: Int?

    /// The hero reads as "focused" when its card Button (single-item) or any page dot (multi-item) is.
    private var isHeroFocused: Bool {
        isFocused || focusedDot != nil
    }

    /// Auto-advance cadence for the spotlight (paused while focused).
    private let autoAdvance = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var current: BaseItemDto? {
        items[safe: index] ?? items.first
    }

    var body: some View {
        if let current {
            if items.count > 1 {
                // Multi-item: the card is a non-focusable backdrop; the page dots (in content(for:))
                // are the focusable pager. Auto-advance still pauses while a dot is focused (INV-8).
                heroCard(for: current)
                    .onReceive(autoAdvance) { _ in
                        guard autoAdvanceEnabled, !reduceMotion, focusedDot == nil else { return }
                        step(by: 1)
                    }
            } else {
                // Single-item (covers): the whole card stays ONE focusable Button so a call site's
                // external `.focused(...)` (e.g. BrunoCategoryShelves) binds to it. No dots, no rotate.
                Button {
                    router.route(to: .item(item: current))
                } label: {
                    heroCard(for: current)
                }
                .buttonStyle(BrunoHeroButtonStyle())
                .focused($isFocused)
            }
        }
    }

    private func heroCard(for item: BaseItemDto) -> some View {
        let insets = UIApplication.shared.brunoOverscanInsets
        // +barHeight: the menu bar ROW now sits directly above the hero in the LazyVStack (the same
        // barHeight the old pinned inset used to reserve — geometry preserved), so the hero's measured
        // layout box starts barHeight lower. The backdrop is bottom-pinned, so its upward spill must clear
        // the overscan strip, the bar band, AND the 36pt inter-row gap to reach the physical top —
        // otherwise a lighter ambient strip shows above the hero (the dimmer-short-of-top bug). topBleed
        // is pure background overflow (never measured), so growing it moves no sibling; layoutHeight is
        // untouched (adding barHeight there too would double-count and over-grow the banner).
        // +rowSpacing: the LazyVStack row spacing between the menu-bar row and the hero row. Without this
        // term the bleed lands one gap short. Most hero-bleed hosts (Kids/Movies/TV) use spacing: 36 (the
        // default); Home tightened to 24 and passes rowSpacing: 24 so its bleed still reaches the top.
        let topBleed = bleedsTop ? insets.top + BrunoMenuBar.barHeight + rowSpacing : 0
        // Three independent knobs (see swift-reference / hero notes):
        //  • layoutHeight  — the ONLY height the parent VStack measures, so it alone fixes the banner's
        //    bottom edge and the shelves below. extraHeight grows it downward (Home restores the
        //    wordmark-row space the overlay vacated).
        //  • visualHeight  — how tall the backdrop DRAWS. It lives in a `.background` (never measured by
        //    the parent), bottom-pinned to the layout box, so its surplus over layoutHeight spills
        //    UPWARD behind the tab bar — exactly topBleed's worth, landing the source's true top at the
        //    physical screen top (full-bleed top) without moving any sibling.
        //  • imageAnchor   — which slice of the (overflowing) fill survives the crop. .top keeps the
        //    source's true top; .center balances it. Replaces the old magic offset.
        // ×0.83: hero runs 17% shorter than its natural height so the first content shelf always peeks
        // below it (and the bottom-pinned title block sits closer to the menu). Applies to every tab —
        // layoutHeight is shared by all BrunoHeroView callers. Safe for the top-bleed: visualHeight =
        // layoutHeight + topBleed, so layoutHeight cancels in the backdrop-top math and the art still
        // reaches the physical top. See docs/BRUNO_HERO.md.
        let layoutHeight = (720 + extraHeight) * 0.83
        let visualHeight = layoutHeight + topBleed
        return ZStack(alignment: .bottomLeading) {
            // Left scrim moved onto the backdrop box below (.background) so it covers the full visible
            // art, including the strip that bleeds up behind the menu.
            // Bottom darkening scrim for copy legibility — fades out by center (top half stays as art).
            // ⚠ LOAD-BEARING: this gradient is also required for the hero to hold its full layoutHeight —
            // removing it pushes the first shelf off-screen when the hero is focused (verified A/B,
            // 2026-06-27). Do not delete; see docs/BRUNO_HERO.md.
            LinearGradient(
                colors: [Color.bruno.page, .clear],
                startPoint: .bottom,
                endPoint: .center
            )
            content(for: item)
                // +overscan keeps the copy title-safe after the card bleeds left to the screen edge.
                    .padding(.leading, 50 + insets.left)
                    .padding(.bottom, 50)
                    .padding(.trailing, 600)
        }
        .frame(maxWidth: .infinity)
        .frame(height: layoutHeight)
        .background(alignment: .bottom) {
            // The drawn backdrop: taller than the layout box, bottom-pinned so the surplus spills up
            // behind the nav. A page-color fill reserves the frame from first render (anti-jump).
            ZStack(alignment: imageAnchor) {
                Color.bruno.page
                ImageView(item.imageSource(.backdrop, maxWidth: 1920))
                    .aspectRatio(contentMode: .fill)
            }
            .frame(maxWidth: .infinity)
            .frame(height: visualHeight, alignment: imageAnchor)
            .clipped()
            // Left scrim for copy legibility — applied to the backdrop box (visualHeight) so its top
            // edge reaches the physical top with the art. In the front (layoutHeight) box its top edge
            // sat below the menu, leaving a bright strip behind the nav and a hard horizontal seam.
            .overlay {
                LinearGradient(
                    colors: [Color.bruno.page.opacity(0.96), Color.bruno.page.opacity(0.1)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .id(item.id)
            .transition(.opacity)
        }
        // Full-bleed horizontally: negate the ScrollView's title-safe content inset so the backdrop +
        // scrims reach the physical screen edges. (Top bleed is produced by visualHeight spilling up.)
        .padding(.horizontal, -insets.left)
    }

    /// Which vertical slice of the filled backdrop survives the crop. `.top` shows the source's true
    /// top (subjects sit lower, clear of the nav); `.center` balances top and bottom.
    private var imageAnchor: Alignment {
        .top
    }

    @ViewBuilder
    private func content(for item: BaseItemDto) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow.uppercased())
                .font(.brunoBody(18, weight: .semibold))
                .tracking(5)
                .foregroundStyle(Color.bruno.accent)

            Text(item.displayTitle)
                .font(.brunoDisplay(72, weight: .semibold))
                .foregroundStyle(Color.bruno.fg)
                .lineLimit(2)

            Text(metaLine(for: item))
                .font(.brunoBody(22))
                .foregroundStyle(Color.bruno.fgMuted)

            if let overview = item.overview {
                Text(overview)
                    .font(.brunoBody(22))
                    .foregroundStyle(Color.bruno.fgMuted)
                    .lineLimit(3)
            }

            // Non-focusable affordances: the hero itself is the focus target, so these are
            // hints for what Select does — they brighten while the hero is focused.
            HStack(spacing: 18) {
                heroPill("Play", systemImage: "play.fill", prominent: true)
                heroPill("More Info", systemImage: "info.circle", prominent: false)
            }
            .padding(.top, 6)

            if items.count > 1 {
                // Focusable page dots = the manual L/R pager (the dots are "a shelf of their own").
                // Each is a chrome-less button; the row is a .focusSection() so LEFT/RIGHT move between
                // dots and UP/DOWN escape to the menu bar / first shelf with no .onMoveCommand sink.
                HStack(spacing: 10) {
                    ForEach(items.indices, id: \.self) { offset in
                        Button {
                            router.route(to: .item(item: item))
                        } label: {
                            dot(for: offset)
                        }
                        .buttonStyle(BrunoHeroButtonStyle())
                        .focused($focusedDot, equals: offset)
                        .accessibilityLabel("Spotlight \(offset + 1) of \(items.count)")
                    }
                }
                .padding(.top, 8)
                .focusSection()
                .backport
                .defaultFocus($focusedDot, index)
                // Move-to-select paging: landing focus on a dot pages the spotlight to it. The
                // `focused != index` guard skips a redundant crossfade when entering on the current dot.
                .onChange(of: focusedDot) { _, focused in
                    if let focused, focused != index { step(to: focused) }
                }
            }
        }
    }

    private func heroPill(_ title: String, systemImage: String, prominent: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.brunoBody(24, weight: .semibold))
            .foregroundStyle(prominent && isHeroFocused ? Color.bruno.page : Color.bruno.fg)
            .padding(.horizontal, 30)
            .padding(.vertical, 12)
            .background {
                Capsule()
                    .fill(
                        prominent
                            ? (isHeroFocused ? Color.bruno.accent : Color.bruno.fg.opacity(0.18))
                            : Color.bruno.fg.opacity(0.12)
                    )
            }
    }

    /// One page-indicator dot: accent-filled for the current spotlight, with a focus halo + lift while
    /// it holds focus. The ring and scale are opacity/transform on an always-present view (INV-10 —
    /// never `if`-inserted), and the lift honors reduce-motion (INV-9).
    private func dot(for offset: Int) -> some View {
        let isCurrent = offset == index
        let hasFocus = focusedDot == offset
        return Circle()
            .fill(isCurrent ? Color.bruno.accent : Color.bruno.fgSubtle.opacity(0.4))
            .frame(width: 14, height: 14)
            .overlay {
                Circle()
                    .stroke(Color.bruno.accent, lineWidth: 3)
                    .padding(-6)
                    .opacity(hasFocus ? 1 : 0)
            }
            .scaleEffect(hasFocus ? 1.4 : 1.0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hasFocus)
    }

    private func step(by delta: Int) {
        guard items.count > 1 else { return }
        let count = items.count
        let next = ((index + delta) % count + count) % count
        withAnimation(.easeInOut(duration: 0.45)) {
            index = next
        }
    }

    /// Page directly to `target` — the dot the focus cursor landed on. Honors reduce-motion (INV-9).
    private func step(to target: Int) {
        guard items.indices.contains(target) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
            index = target
        }
    }

    private func metaLine(for item: BaseItemDto) -> String {
        var parts: [String] = []
        if let year = item.productionYear { parts.append(String(year)) }
        if let genre = item.genres?.first { parts.append(genre) }
        if let rating = item.communityRating { parts.append("★ \(String(format: "%.1f", rating))") }
        return parts.joined(separator: "  ·  ")
    }
}

// MARK: - BrunoHeroButtonStyle

//
// A chrome-less button style: no scale, no system focus halo. The hero communicates focus
// through its own affordances (the brightened Play pill) instead of a card highlight, so a
// click down from the menu "invisibly" lands on the hero.
private struct BrunoHeroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - Overscan

extension UIApplication {

    /// The key window's tvOS title-safe overscan insets. The page ScrollView insets its content to
    /// this, so Bruno's full-bleed hero negates it to reach the physical screen edges; the Home
    /// wordmark (overlaid on the top-bleeding hero) re-applies it to stay title-safe.
    var brunoOverscanInsets: UIEdgeInsets {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets ?? .zero
    }
}
