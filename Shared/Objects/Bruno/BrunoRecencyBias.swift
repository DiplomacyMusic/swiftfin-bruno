//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// MARK: - BrunoRecencyBias

//
// The single source of truth for Bruno's "modern cutoff" (owner request). Used by the Home path's
// standard-genre `genreQuery` (server-side year filter) and the Classic Romance carve-out to split
// modern titles from classics. The genre BROWSE shelves no longer apply this cutoff — they render
// each sub-genre's full membership (see BrunoBoxSetShelvesView.performLoad).
enum BrunoRecencyBias {

    /// First "modern" production year. Used by `BrunoHomePlan.genreQuery` (year filter) and the
    /// Classic Romance split. 1985 matches the existing Classic Romance cutoff, so the app uses one line.
    static let modernCutoff = 1985
}
