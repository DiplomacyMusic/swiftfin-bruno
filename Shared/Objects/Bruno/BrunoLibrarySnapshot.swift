//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

// MARK: - BrunoLibrarySnapshot

//
// Fetched ONCE (async) when the home refreshes; after that `BrunoHomePlan.build` is pure
// over it (plan §D/§E). The owner's library is curated as 7 favorited "group" BoxSets
// (Directors, Decades, Studios, Genres, Curated, Seasonal, New Releases) whose children are
// the real sub-collections. We never hardcode IDs — everything is derived here from the
// live library (validated in BRUNO_NOTES.md §Live library snapshot).
//
// Codable + Sendable so it can be persisted to disk (instant relaunch — see BrunoHomeCache) and
// crossed to a detached encode/decode task without `nonisolated(unsafe)`. All stored members are
// already Sendable/Codable (`BaseItemDto` is both).
struct BrunoLibrarySnapshot: Codable {

    /// The favorited top-level group BoxSets (the spec's 7 groups), in server order.
    let favoriteGroupBoxSets: [BaseItemDto]
    /// For each group BoxSet name → its child items (sub-BoxSets for most groups).
    let childrenByGroupName: [String: [BaseItemDto]]
    /// Distinct genre names present in the library.
    let genres: [String]
    /// Distinct production years present (for the "year" explore generator).
    let years: [Int]
    /// The standalone franchise BoxSets — every box set that is NOT a curated group or a group's
    /// child — i.e. the members of the synthetic "Boxed Sets" tile. Fetched here so the single shared
    /// builder (`BrunoCollectionCategory.fromSnapshot`) can surface Boxed Sets on Home AND Collections
    /// from one snapshot. Optional so older on-disk payloads (no key) decode to nil (see BrunoHomeCache).
    let franchiseBoxSets: [BaseItemDto]?
    /// Per decade sub-group NAME → the single "best of the decade" film whose cover backs that decade's
    /// Eras card (highest curated `bruno-sig:NN` significance, else highest community rating). Resolved
    /// here so the render path stays pure — no per-cell network on the Home scroll surface. Optional so
    /// older on-disk payloads (no key) decode to nil and fall back to the gradient card (like
    /// `franchiseBoxSets`).
    let decadeBestOf: [String: BaseItemDto]?

    static var empty: BrunoLibrarySnapshot {
        .init(
            favoriteGroupBoxSets: [],
            childrenByGroupName: [:],
            genres: [],
            years: [],
            franchiseBoxSets: nil,
            decadeBestOf: nil
        )
    }

    // Case-insensitive group lookups (group names are owner-authored).
    private func group(_ name: String) -> [BaseItemDto] {
        if let exact = childrenByGroupName[name] { return exact }
        let lower = name.lowercased()
        for (key, value) in childrenByGroupName where key.lowercased() == lower {
            return value
        }
        return []
    }

    var directorBoxSets: [BaseItemDto] {
        group("Directors")
    }

    /// The pre-built "Movie Stars" actor BoxSets (each an actor's films). Mirrors `directorBoxSets` so
    /// the Collections tail's actor-in-focus generator works exactly like the director one. "Movie Stars"
    /// is a favorited group, so its children are already fetched by `load()` — no new fetch.
    var actorBoxSets: [BaseItemDto] {
        group("Movie Stars")
    }

    var decadeBoxSets: [BaseItemDto] {
        group("Decades")
    }

    /// The "best of the decade" film backing a decade's Eras card, by decade sub-group name
    /// (case-insensitive). nil ⇒ no resolved best-of (old payload or empty decade) → gradient fallback.
    func decadeBestOfFilm(for decadeName: String) -> BaseItemDto? {
        guard let map = decadeBestOf else { return nil }
        if let exact = map[decadeName] { return exact }
        let lower = decadeName.lowercased()
        return map.first { $0.key.lowercased() == lower }?.value
    }

    var studioBoxSets: [BaseItemDto] {
        group("Studios")
    }

    var genreBoxSets: [BaseItemDto] {
        group("Genres")
    }

    var curatedBoxSets: [BaseItemDto] {
        group("Curated")
    }

    var seasonalBoxSets: [BaseItemDto] {
        group("Seasonal")
    }

    /// The favorited "Rewatchables" BoxSet (the podcast films), if present. Its members are MOVIES (not
    /// sub-collections), so Home queries it via parentID; the Rewatchables cover buckets them by genre.
    var rewatchablesBoxSet: BaseItemDto? {
        favoriteGroupBoxSets.first { $0.name?.lowercased() == "rewatchables" }
    }

    var isEmpty: Bool {
        favoriteGroupBoxSets.isEmpty && genres.isEmpty
    }
}

extension BrunoLibrarySnapshot {

    /// Loads the snapshot from the live library. Best-effort: any sub-fetch that fails or
    /// returns nothing simply yields an empty slice, and dependent shelves are dropped later.
    static func load(client: JellyfinClient, userID: String) async -> BrunoLibrarySnapshot {
        async let groupsTask = fetchGroupBoxSets(client: client, userID: userID)
        async let genresTask = fetchGenres(client: client, userID: userID)
        async let yearsTask = fetchYears(client: client, userID: userID)
        // Every box set in the library — narrowed to standalone franchises below. Fetched up front and
        // concurrently so the synthetic "Boxed Sets" tile resolves from this one snapshot (no separate
        // per-surface fetch). Awaited on the single return path after the children are known.
        async let allBoxSetsTask = fetchAllBoxSets(client: client, userID: userID)

        let groups = await groupsTask

        // Fetch each group's children concurrently.
        var childrenByName: [String: [BaseItemDto]] = [:]
        await withTaskGroup(of: (String, [BaseItemDto]).self) { taskGroup in
            for boxSet in groups {
                guard let id = boxSet.id, let name = boxSet.name else { continue }
                taskGroup.addTask {
                    let children = await fetchChildren(client: client, userID: userID, parentID: id)
                    return (name, children)
                }
            }
            for await (name, children) in taskGroup {
                childrenByName[name] = children
            }
        }

        // Boxed Sets = every box set NOT already a curated group, a group's child, or a name-duplicate
        // of a Directors child (those belong under Directors). This is the filter the Collections hub
        // used to run locally, centralized here so Home and Collections share one franchise list.
        let groupIDs = Set(groups.compactMap(\.id))
        let childIDs = Set(childrenByName.values.flatMap(\.self).compactMap(\.id))
        // Inline trim+lowercase (not the tvOS-only `String.trimmedLowercased`) so this Shared file stays
        // buildable in every target; same normalization for both sides of the name comparison.
        let directorNames = Set(
            (childrenByName.first { $0.key.lowercased() == "directors" }?.value ?? [])
                .compactMap { $0.name?.trimmingCharacters(in: .whitespaces).lowercased() }
        )
        let franchiseBoxSets = await allBoxSetsTask.filter { boxSet in
            guard let id = boxSet.id else { return false }
            guard !groupIDs.contains(id), !childIDs.contains(id) else { return false }
            if let name = boxSet.name?.trimmingCharacters(in: .whitespaces).lowercased(),
               directorNames.contains(name) { return false }
            return true
        }

        // Best-of film per decade (for the Eras card backgrounds). For each decade sub-BoxSet, fetch its
        // films WITH tags (MinimumFields omits them), rating-sorted, and pick the highest curated
        // significance (bruno-sig:NN) else the top-rated. Resolved here so the render path stays pure (no
        // per-cell network on the Home scroll surface). Concurrent across decades.
        let decadeChildren = childrenByName.first { $0.key.lowercased() == "decades" }?.value ?? []
        var decadeBestOf: [String: BaseItemDto] = [:]
        await withTaskGroup(of: (String, BaseItemDto?).self) { taskGroup in
            for decade in decadeChildren {
                guard let id = decade.id, let name = decade.name else { continue }
                taskGroup.addTask {
                    await (name, fetchDecadeBestOf(client: client, userID: userID, parentID: id))
                }
            }
            for await (name, film) in taskGroup where film != nil {
                decadeBestOf[name] = film
            }
        }

        return await BrunoLibrarySnapshot(
            favoriteGroupBoxSets: groups,
            childrenByGroupName: childrenByName,
            genres: genresTask,
            years: yearsTask,
            franchiseBoxSets: franchiseBoxSets,
            decadeBestOf: decadeBestOf
        )
    }

    private static func fetchGroupBoxSets(client: JellyfinClient, userID: String) async -> [BaseItemDto] {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.isRecursive = true
        parameters.includeItemTypes = [.boxSet]
        parameters.filters = [.isFavorite]
        parameters.fields = .MinimumFields
        parameters.limit = 50
        return await send(client: client, parameters: parameters)
    }

    private static func fetchChildren(client: JellyfinClient, userID: String, parentID: String) async -> [BaseItemDto] {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.parentID = parentID
        // .genres so the child movies/series carry genre tags for the hero child-safety filter
        // (brunoHeroEligible); MinimumFields omits them, which would make the filter a silent no-op.
        parameters.fields = .MinimumFields + [.genres]
        parameters.enableUserData = true
        parameters.limit = 200
        return await send(client: client, parameters: parameters)
    }

    /// The "best of the decade" film for a decade sub-BoxSet: highest curated significance
    /// (`bruno-sig:NN` tag), else the highest community rating. Fetches a rating-sorted window WITH tags
    /// (MinimumFields omits them); a private home library's decade fits within the cap, so this is the
    /// exact best-of in practice (a larger decade degrades gracefully to the top-of-window pick).
    private static func fetchDecadeBestOf(client: JellyfinClient, userID: String, parentID: String) async -> BaseItemDto? {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.parentID = parentID
        parameters.isRecursive = true
        parameters.includeItemTypes = [.movie]
        parameters.fields = .MinimumFields + [.tags]
        parameters.sortBy = [.communityRating]
        parameters.sortOrder = [.descending]
        parameters.limit = 100
        let films = await send(client: client, parameters: parameters)
        guard films.isNotEmpty else { return nil }
        let bySignificance = films
            .compactMap { film in brunoSignificance(film).map { (film, $0) } }
            .max { $0.1 < $1.1 }?
            .0
        return bySignificance ?? films.first
    }

    /// Significance score from a `bruno-sig:<NN>` tag (the enrichment pipeline's "best of" signal),
    /// nil when absent. Inlined here because the drill-in's copy is tvOS-only (BrunoBoxSetShelvesView).
    private static func brunoSignificance(_ item: BaseItemDto) -> Int? {
        guard let tag = item.tags?.first(where: { $0.hasPrefix("bruno-sig:") }) else { return nil }
        return Int(tag.dropFirst("bruno-sig:".count))
    }

    private static func fetchAllBoxSets(client: JellyfinClient, userID: String) async -> [BaseItemDto] {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.isRecursive = true
        parameters.includeItemTypes = [.boxSet]
        // .childCount feeds the "N films" line on the franchise cards + the weighted preview; it is
        // NOT in MinimumFields, so without it the count is nil and that line is hidden.
        parameters.fields = .MinimumFields + [.childCount]
        parameters.enableUserData = true
        parameters.sortBy = [.name]
        parameters.sortOrder = [.ascending]
        // The library has 300+ box sets; fetch them all (a 200 cap silently dropped late-alphabet
        // franchises like Star Wars / The Lord of the Rings).
        parameters.limit = 1000
        return await send(client: client, parameters: parameters)
    }

    private static func fetchGenres(client: JellyfinClient, userID: String) async -> [String] {
        var parameters = Paths.GetGenresParameters()
        parameters.userID = userID
        parameters.includeItemTypes = [.movie, .series]
        parameters.limit = 60
        do {
            let response = try await client.send(Paths.getGenres(parameters: parameters))
            return (response.value.items ?? []).compactMap(\.name)
        } catch {
            return []
        }
    }

    private static func fetchYears(client: JellyfinClient, userID: String) async -> [Int] {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.isRecursive = true
        parameters.includeItemTypes = [.movie]
        parameters.sortBy = [.productionYear]
        parameters.sortOrder = [.descending]
        parameters.fields = .MinimumFields
        parameters.limit = 400
        let items = await send(client: client, parameters: parameters)
        let years = Set(items.compactMap(\.productionYear)).filter { $0 > 1900 }
        return years.sorted()
    }

    private static func send(client: JellyfinClient, parameters: Paths.GetItemsParameters) async -> [BaseItemDto] {
        do {
            let response = try await client.send(Paths.getItems(parameters: parameters))
            return response.value.items ?? []
        } catch {
            return []
        }
    }
}

// MARK: - Shared cache

extension BrunoLibrarySnapshot {

    /// In-memory cache so navigating Home -> Collections reuses the snapshot Home just loaded
    /// instead of refetching the whole library each time (the "slow loads between pages"). Short
    /// TTL; keyed by userID so a user switch never serves stale data; explicit refreshes bypass it.
    private actor Cache {
        private var snapshot: BrunoLibrarySnapshot?
        private var userID: String?
        private var loadedAt: Date?

        func value(userID: String, maxAge: TimeInterval) -> BrunoLibrarySnapshot? {
            guard self.userID == userID,
                  let snapshot, let loadedAt,
                  !snapshot.isEmpty,
                  // A snapshot persisted before `franchiseBoxSets` / `decadeBestOf` existed decodes that
                  // field to nil. A fresh `load` ALWAYS sets both (possibly []), so nil means "never
                  // computed" — treat it as a miss so `loadShared` does a real fetch and fills the Boxed
                  // Sets list AND the decade best-of covers, instead of serving (and re-seeding) a
                  // snapshot missing them all session (e.g. a hydrate that seeded this cache).
                  snapshot.franchiseBoxSets != nil,
                  snapshot.decadeBestOf != nil,
                  Date().timeIntervalSince(loadedAt) < maxAge
            else { return nil }
            return snapshot
        }

        func store(_ snapshot: BrunoLibrarySnapshot, userID: String) {
            guard !snapshot.isEmpty else { return }
            self.snapshot = snapshot
            self.userID = userID
            self.loadedAt = Date()
        }
    }

    private static let cache = Cache()

    /// Like `load`, but reuses a recent in-memory snapshot for the same user (default 5 min). Pass
    /// `forceReload: true` for explicit refreshes (still stores the fresh result so peers can reuse).
    static func loadShared(
        client: JellyfinClient,
        userID: String,
        maxAge: TimeInterval = 300,
        forceReload: Bool = false
    ) async -> BrunoLibrarySnapshot {
        if !forceReload, let cached = await cache.value(userID: userID, maxAge: maxAge) {
            return cached
        }
        let fresh = await load(client: client, userID: userID)
        await cache.store(fresh, userID: userID)
        return fresh
    }

    /// Seed the in-memory cache with a snapshot we already have (e.g. one hydrated from disk on
    /// launch), so Collections / drill-ins reuse it this session instead of refetching.
    static func seedCache(_ snapshot: BrunoLibrarySnapshot, userID: String) async {
        await cache.store(snapshot, userID: userID)
    }
}
