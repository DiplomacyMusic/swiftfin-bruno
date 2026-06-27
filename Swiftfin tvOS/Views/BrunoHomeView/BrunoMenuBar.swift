//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// MARK: - BrunoMenuBar (tvOS only)

//
// The Bruno top menu bar — a focusable pill row that REPLACES the stock SwiftUI `TabView` tab bar.
// The system bar was a UIKit surface with no focus binding, so the only way to reach it from content
// was Menu/Back; UP did nothing. A real focusable row lets the focus engine carry UP from the top
// content row straight into the bar — it is the first `.focusSection()` row of each tab/cover's
// LazyVStack (via BrunoScrollingMenuBar / BrunoCoverMenuBarRow), so UP/DOWN traverse between rows
// naturally; no special routing in MainTabView.
//
// Pills switch on Select (press), NEVER on focus — traversing the bar must not switch tabs (that would
// mount/teardown tab state mid-traversal). Label content/icon-only comes from TabItem.labelStyle, so
// Search/Settings render icon-only exactly as they did under the stock `.tabItem`.
struct BrunoMenuBar: View {

    let tabs: [TabItem]

    @Binding
    var selection: String?

    /// Focus binding for the pill row. Owned by the wrapping scrolling-row component
    /// (BrunoScrollingMenuBar / BrunoCoverMenuBarRow) — there is no pinned bar for MainTabView to drive
    /// focus onto anymore; each tab/cover's bar manages its own focus.
    var focus: FocusState<String?>.Binding

    /// Fixed height of the menu bar's SCROLLING ROW. The bar is the first row of each tab/cover's
    /// LazyVStack (BrunoScrollingMenuBar / BrunoCoverMenuBarRow), not a pinned inset — it scrolls away
    /// like every shelf. Each component applies `.frame(height: barHeight)` so the row's frame is fixed
    /// (INV-1: independent of focus/content). Must be ≥ the bar's intrinsic height (~108pt: brunoBody(28)
    /// pill + 14·2 + HStack 12·2 + 8/14 bar padding) or `.frame(height:)` undersizes the pill box. Also
    /// read by BrunoHeroView's `topBleed` (the row reserves the same barHeight above the hero the old
    /// pinned inset used to, so the hero geometry is unchanged).
    static let barHeight: CGFloat = 116

    var body: some View {
        HStack(spacing: 12) {
            ForEach(tabs) { tab in
                BrunoMenuPill(tab: tab, isSelected: tab.id == selection) {
                    selection = tab.id
                }
                .focused(focus, equals: tab.id)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        // Floating dark-glass pill group (the stock-bar look) so the hero art reads through and around
        // it. The bar is the scrolling row above the hero, so this capsule sits over the backdrop that
        // bleeds up into the bar's region from the hero row below.
        .background {
            Capsule(style: .continuous)
                .fill(.black.opacity(0.4))
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.bruno.fg.opacity(0.10), lineWidth: 1)
                }
        }
        // Centre the hugged capsule and float it just below the title-safe top edge; the hero backdrop
        // fills the strip above and behind it.
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - BrunoMenuPill

//
// One menu entry, styled on BrunoSelectorCard's pill vocabulary (translucent wash idle, accent fill
// when selected, 3px accent focus ring + 1.05 lift on focus) but carrying an icon + title so it
// matches the original tab labels.
private struct BrunoMenuPill: View {

    let tab: TabItem
    let isSelected: Bool
    let action: () -> Void

    @FocusState
    private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Label(tab.title, systemImage: tab.systemImage)
                // TabItem encodes .iconOnly for Search/Settings, .titleAndIcon for the rest. The
                // existential `any LabelStyle` must be erased here (same as the old MainTabView tabItem)
                // or the opened-existential type escapes the ViewBuilder ("any View cannot conform").
                    .labelStyle(tab.labelStyle)
                    .eraseToAnyView()
                    .font(.brunoBody(28, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.bruno.page : Color.bruno.fg)
                    .lineLimit(1)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 14)
                    .background {
                        Capsule(style: .continuous)
                            .fill(
                                isSelected
                                    ? Color.bruno.accent
                                    : Color.bruno.fg.opacity(isFocused ? 0.22 : 0.12)
                            )
                    }
                    .overlay {
                        // Accent focus ring, opacity-toggled (never if-inserted) so it cross-fades with the
                        // scale/fill instead of popping — matches BrunoSelectorCard.
                        Capsule(style: .continuous)
                            .stroke(Color.bruno.accent, lineWidth: 3)
                            .opacity(isFocused && !isSelected ? 1 : 0)
                    }
                    .scaleEffect(isFocused ? 1.05 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: isFocused)
        }
        // Chrome-less: OUR accent capsule is the focus cursor, so suppress the system button highlight.
        .buttonStyle(BrunoMenuPillButtonStyle())
        .focused($isFocused)
    }
}

// MARK: - BrunoMenuPillButtonStyle

private struct BrunoMenuPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - brunoTabIsActive

extension EnvironmentValues {

    /// True when the enclosing tab is the active (visible) one. The custom container (MainTabView)
    /// keeps every tab mounted, so it injects this per tab to let content deep in the tree (e.g.
    /// BrunoShelfView) cancel prefetch / pause work while hidden — hidden tabs never fire onDisappear.
    @Entry
    var brunoTabIsActive: Bool = true
}
