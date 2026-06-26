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
// content row straight into the bar (the section parent in MainTabView does the UP/DOWN routing).
//
// Pills switch on Select (press), NEVER on focus — traversing the bar must not switch tabs (that would
// mount/teardown tab state mid-traversal). Label content/icon-only comes from TabItem.labelStyle, so
// Search/Settings render icon-only exactly as they did under the stock `.tabItem`.
struct BrunoMenuBar: View {

    let tabs: [TabItem]

    @Binding
    var selection: String?

    /// Owned by MainTabView so it can drive focus onto the selected pill when Menu is pressed in content.
    var focus: FocusState<String?>.Binding

    var body: some View {
        HStack(spacing: 12) {
            ForEach(tabs) { tab in
                BrunoMenuPill(tab: tab, isSelected: tab.id == selection) {
                    selection = tab.id
                }
                .focused(focus, equals: tab.id)
            }
        }
        .padding(.horizontal, EdgeInsets.edgePadding)
        .padding(.top, 24)
        .padding(.bottom, 18)
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
