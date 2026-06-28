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

// MARK: - BrunoHeroWordmark

//
// The BRUNO wordmark that floats at the top-left of a hero, lifted up onto the menu bar's centerline.
// Shared across every hero-bleed tab (Home / Collections / Movies / TV / Kids) via `.brunoHeroWordmark()`
// so the brand sits identically on all of them. See docs/BRUNO_HERO_LAYOUT_MAP.md §4.
struct BrunoHeroWordmark: View {

    /// Home appends the build stamp (a "which build am I looking at?" diagnostic); the other tabs don't.
    var showBuildStamp: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text("BRUNO")
                .font(.brunoDisplay(40, weight: .bold))
                .tracking(6)
                .foregroundStyle(Color.bruno.fg)
            Circle()
                .fill(Color.bruno.accent)
                .frame(width: 12, height: 12)

            if showBuildStamp {
                Spacer()
                // Build stamp: the app executable's build time. Auto-updates every build, so it's an
                // unambiguous "which build am I looking at?" marker. (Temporary diagnostic.)
                Text(Self.buildStamp)
                    .font(.brunoBody(20, weight: .semibold))
                    .foregroundStyle(Color.bruno.accent)
            }
        }
    }

    private static var buildStamp: String {
        guard let executableURL = Bundle.main.executableURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path),
              let date = attributes[.modificationDate] as? Date
        else { return "BUILD —" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d · HH:mm:ss"
        return "BUILD \(formatter.string(from: date))"
    }
}

extension View {

    /// Overlay the BRUNO wordmark onto a hero, lifted onto the menu bar's centerline. Apply to the
    /// `BrunoHeroView` row on every hero-bleed tab. The offset is keyed off `BrunoMenuBar.barHeight` and
    /// the 36pt LazyVStack row spacing (both constant across tabs), so it lands identically everywhere —
    /// see docs/BRUNO_HERO_LAYOUT_MAP.md §4. Because it's an `.overlay`, it never affects sibling layout.
    func brunoHeroWordmark(showBuildStamp: Bool = false) -> some View {
        overlay(alignment: .top) {
            BrunoHeroWordmark(showBuildStamp: showBuildStamp)
                .padding(.horizontal, 50)
                // Raise by the hero's drop below the bar (barHeight + 36 row spacing), re-center within
                // the bar (~48pt wordmark cap height), then a 10pt visual nudge down.
                .padding(.top, -(BrunoMenuBar.barHeight + 36) + (BrunoMenuBar.barHeight - 48) / 2 - 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
