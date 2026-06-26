//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Factory
import SwiftUI

// TODO: move popup to router
//       - or, make tab view environment object

// TODO: fix weird tvOS icon rendering
struct MainTabView: View {

    @InjectedObject(\.deepLinkHandler)
    private var deepLinkHandler

    // Live reference published to pushed hero covers (Decades/Genres) so their in-cover menu bar can
    // reach the tab list/selection. tvOS only; harmless elsewhere.
    @Injected(\.brunoTabBridge)
    private var brunoTabBridge

    #if os(iOS)
    @StateObject
    private var tabCoordinator = TabCoordinator {
        TabItem.home
        TabItem.search
        TabItem.media
    }
    #else
    @StateObject
    private var tabCoordinator = TabCoordinator {
        // Bruno tvOS IA: Search · Home · Collections · Movies · TV Shows · Kids · Settings.
        // Search (icon) leads, Settings (icon) trails; the app still opens on Home (see onAppear).
        TabItem.search
        TabItem.home
        TabItem.collections
        TabItem.movies
        TabItem.tvShows
        TabItem.kids
        TabItem.settings
    }
    #endif

    private func routePendingDeepLink() {
        guard let deepLink = deepLinkHandler.consumePendingDeepLink() else { return }

        Task { @MainActor in
            do {
                let route = try await deepLinkHandler.route(for: deepLink)
                tabCoordinator.route(to: route)
            } catch {
                // TODO: surface deep link failures in UI.
            }
        }
    }

    private func landOnHomeThenDeepLink() {
        // Land on Home even though Search is the leading tab.
        if tabCoordinator.selectedTabID == nil {
            tabCoordinator.selectedTabID = "home"
        }
        routePendingDeepLink()
    }

    #if os(tvOS)

    // Bruno tvOS: a custom focusable top menu bar (BrunoMenuBar) REPLACES the stock TabView tab bar so
    // UP from the top content row reaches it via the normal focus engine. See
    // docs/.../plan — the system bar had no focus binding, so UP did nothing there.

    /// Focus target for the bar's pills — set when Menu is pressed in content to surface the bar.
    @FocusState
    private var barFocus: String?

    /// Default-focus scope so launch / DOWN-from-bar land in CONTENT, not the bar.
    @Namespace
    private var rootNamespace

    /// Visited tab ids in selection order (most-recent LAST). Home is mounted at launch; every other
    /// tab mounts the first time it's selected, then stays alive so its scroll/nav/viewmodel state
    /// survives switching. Drives lazy-mount + RAM-gated LRU eviction (see mountedIDs).
    @State
    private var recency: [String] = ["home"]

    /// Apple TV HD (~2 GB) jetsams once several poster grids are retained (hidden tabs never fire
    /// onDisappear, so their decoded posters stay alive). On low-RAM hardware keep only Home + the two
    /// most-recent tabs; 4K-class (≥ ~2.5 GB) keeps full keep-alive. INV-safe: a re-mounted tab re-runs
    /// the streaming reveal and repaints instantly from the seed-keyed disk cache (INV-5).
    private var isMemoryConstrained: Bool {
        ProcessInfo.processInfo.physicalMemory < 2_500_000_000
    }

    private var mountedIDs: Set<String> {
        guard isMemoryConstrained else { return Set(recency) }
        var keep = Set(recency.suffix(2))
        keep.insert("home")
        return keep
    }

    private var brunoTabView: some View {
        // Bar and content are focus PEERS under one `.focusScope`, the bar floating in a `ZStack(.top)` OVER
        // each tab's full-bleed ambient backdrop. The non-overlap that lets UP reach the bar lives in each
        // tab now, not here: every page wraps its SCROLL CONTENT in `brunoBelowMenuBar()` — a REAL
        // `padding(.top, barHeight)` + `.focusSection()` — so the content's focus frame starts strictly
        // below the bar's band (a `safeAreaInset` left the frame full-screen, overlapping the bar, so UP
        // resolved to itself — the bug). The ambient stays a sibling OUTSIDE that inset, so it still bleeds
        // to the physical top behind the translucent pills. We therefore do NOT inset or section the content
        // stack here — only bias default focus into it and route Menu to the bar.
        //
        // REQUIRES every tab's page view to RESPECT the top safe area (they use
        // `.ignoresSafeArea(edges: [.horizontal, .bottom])`) and to apply `brunoBelowMenuBar()` to its
        // scroll content. Stock utility tabs (Search/Settings) get the wrapper at their TabItem call site.
        ZStack(alignment: .top) {
            ZStack {
                ForEach(tabCoordinator.tabs, id: \.item.id) { tab in
                    if mountedIDs.contains(tab.item.id) {
                        NavigationInjectionView(coordinator: tab.coordinator) {
                            tab.item.content
                        }
                        .environmentObject(tabCoordinator)
                        .environment(\.tabItemSelected, tab.publisher)
                        .environment(\.brunoTabIsActive, tab.item.id == tabCoordinator.selectedTabID)
                        .opacity(tab.item.id == tabCoordinator.selectedTabID ? 1 : 0)
                        .allowsHitTesting(tab.item.id == tabCoordinator.selectedTabID)
                        // Removes inactive subtrees from the focus chain — exactly one tab is focusable.
                        .disabled(tab.item.id != tabCoordinator.selectedTabID)
                    }
                }
            }
            .prefersDefaultFocus(in: rootNamespace)
            // Menu from content surfaces the bar (focuses the selected pill); the bar itself has no
            // exit handler, so Menu there falls through to the system and backgrounds the app at root.
            .onExitCommand { barFocus = tabCoordinator.selectedTabID }

            BrunoMenuBar(
                tabs: tabCoordinator.tabs.map(\.item),
                selection: $tabCoordinator.selectedTabID,
                focus: $barFocus
            )
            // alignment:.top so the hugged capsule hugs the box top (keeping BrunoMenuBar's own .top,8 float)
            // instead of vertical-centering in the reserved height and sinking below the title-safe edge.
            .frame(height: BrunoMenuBar.barHeight, alignment: .top)
                .focusSection()
        }
        .focusScope(rootNamespace)
        .background(Color.bruno.page.ignoresSafeArea())
        .onChange(of: tabCoordinator.selectedTabID) { _, newValue in
            guard let newValue else { return }
            recency.removeAll { $0 == newValue }
            recency.append(newValue)
        }
        .onAppear {
            brunoTabBridge.coordinator = tabCoordinator
            landOnHomeThenDeepLink()
        }
        .onReceive(deepLinkHandler.$pendingDeepLink.compactMap(\.self)) { _ in
            routePendingDeepLink()
        }
    }

    var body: some View {
        brunoTabView
    }

    #else

    @ViewBuilder
    var body: some View {
        TabView(selection: $tabCoordinator.selectedTabID) {
            ForEach(tabCoordinator.tabs, id: \.item.id) { tab in
                NavigationInjectionView(
                    coordinator: tab.coordinator
                ) {
                    tab.item.content
                }
                .environmentObject(tabCoordinator)
                .environment(\.tabItemSelected, tab.publisher)
                .tabItem {
                    Label(
                        tab.item.title,
                        systemImage: tab.item.systemImage
                    )
                    .labelStyle(tab.item.labelStyle)
                    .symbolRenderingMode(.monochrome)
                    .eraseToAnyView()
                }
                .tag(tab.item.id)
            }
        }
        .onAppear(perform: landOnHomeThenDeepLink)
        .onReceive(deepLinkHandler.$pendingDeepLink.compactMap(\.self)) { _ in
            routePendingDeepLink()
        }
    }

    #endif
}
