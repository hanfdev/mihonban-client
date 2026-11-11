import Foundation
import Observation

@MainActor @Observable
final class CatalogStore {
    private(set) var albums: [Album] = []
    private(set) var artists: [Artist] = []
    private(set) var tracks: [Track] = []
    private(set) var tracksLoaded = false
    private(set) var loading = false
    private(set) var loadingTracks = false
    private(set) var index = CatalogIndex(albums: [], tracks: [], artists: [], includeHidden: false)
    // Changes whenever the index is rebuilt; screens observe this one value.
    private(set) var revision = UUID()
    private(set) var showHidden = false
    // Seeded catalogs (demo mode) never contact a service.
    private(set) var offline = false
    var error: String?
    // Supplies full albums kept with offline downloads when the service is unreachable.
    @ObservationIgnored var localAlbum: (@MainActor (String) -> Album?)?
    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private let favorites: FavoritesStore
    @ObservationIgnored private var disk: SnapshotStore?
    @ObservationIgnored private var scope = ""
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var albumETag: String?
    @ObservationIgnored private var trackETag: String?
    @ObservationIgnored private var details: [String: Album] = [:]
    @ObservationIgnored private var requests: [String: Task<Album, Error>] = [:]
    @ObservationIgnored private var trackRequest: Task<[Track], Error>?
    #if DEBUG
    // Deterministically exercise session changes after suspended snapshot I/O.
    @ObservationIgnored var albumSnapshotBoundary: (@MainActor () async -> Void)?
    #endif

    init(session: SessionStore, favorites: FavoritesStore) {
        self.session = session
        self.favorites = favorites
    }

    func reset() {
        generation = UUID()
        requests.values.forEach { $0.cancel() }
        requests.removeAll()
        trackRequest?.cancel()
        trackRequest = nil
        albums = []; artists = []; tracks = []; details.removeAll()
        albumETag = nil; trackETag = nil
        tracksLoaded = false; loading = false; loadingTracks = false
        showHidden = false; error = nil; disk = nil; scope = ""; offline = false
        rebuildIndex()
    }

    func connect() async {
        reset()
        guard let client = session.client, let info = session.info, info.ok else { return }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mihonban/" + digest(client.baseURL.absoluteString) + "/catalog", isDirectory: true)
        disk = SnapshotStore(root: root)
        scope = "v1-" + (info.role ?? "guest") + "-visible"
        let token = generation
        if let saved = await disk?.load(scope, as: CatalogSnapshot.self), token == generation {
            apply(saved)
        }
        guard token == generation else { return }
        await refresh()
    }

    func seed(albums: [Album], artists: [Artist], tracks: [Track]) {
        reset()
        self.albums = albums; self.artists = artists; self.tracks = tracks
        albums.forEach { details[$0.id] = $0 }
        tracksLoaded = true
        offline = true
        rebuildIndex()
    }

    func setShowHidden(_ enabled: Bool) async {
        guard session.canSeeHidden, enabled != showHidden else { return }
        generation = UUID()
        requests.values.forEach { $0.cancel() }; requests.removeAll()
        trackRequest?.cancel(); trackRequest = nil
        showHidden = enabled
        albumETag = nil; trackETag = nil
        details.removeAll(); artists = []; tracks = []; tracksLoaded = false
        albums = albums.filter { $0.hidden != true }
        loading = false; loadingTracks = false
        scope = "v1-" + (session.info?.role ?? "guest") + (enabled ? "-hidden" : "-visible")
        rebuildIndex()
        await refresh()
    }

    func refresh() async {
        guard session.client != nil, !loading, !offline else { return }
        loading = true; error = nil
        let token = generation
        let hidden = showHidden && session.canSeeHidden
        let previous = albumETag.map { Versioned(value: albums, etag: $0) }
        defer { if token == generation { loading = false } }
        do {
            async let newAlbums = session.perform { try await $0.catalog(includeHidden: hidden, previous: previous) }
            async let newArtists = session.perform { try await $0.artists(includeHidden: hidden) }
            async let newFavorites = session.perform { try await $0.favorites() }
            let (list, people, picks) = try await (newAlbums, newArtists, newFavorites)
            guard token == generation else { return }
            albums = list.value
            albumETag = list.etag
            artists = people
            favorites.replace(picks)
            rebuildIndex()
            // Revalidate a cached song list with its ETag. A favorites response
            // can already reference songs imported since that list was saved.
            if tracksLoaded || !picks.tracks.isEmpty { await ensureTracks(force: true) }
            guard token == generation else { return }
            await persist()
        } catch {
            if token == generation && !(error is CancellationError) { self.error = describe(error) }
        }
    }

    func ensureTracks(force: Bool = false) async {
        let token = generation
        do { _ = try await requireTracks(force: force) }
        catch { if token == generation && !(error is CancellationError) { self.error = describe(error) } }
    }

    func requireTracks(force: Bool = false) async throws -> [Track] {
        if offline || (tracksLoaded && !force) { return index.tracks }
        let token = generation
        if let request = trackRequest {
            let loaded = try await request.value
            guard token == generation else { throw CancellationError() }
            return loaded
        }
        let hidden = showHidden && session.canSeeHidden
        let previous = tracksLoaded ? Versioned(value: tracks, etag: trackETag) : nil
        let session = session
        let request = Task {
            let loaded = try await session.perform { try await $0.allTracks(includeHidden: hidden, previous: previous) }
            let changed = try await self.applyTracks(loaded, generation: token)
            let result = self.index.tracks
            if changed { await self.persist() }
            guard token == self.generation else { throw CancellationError() }
            return result
        }
        trackRequest = request
        loadingTracks = true
        error = nil
        defer { if token == generation { trackRequest = nil; loadingTracks = false } }
        return try await request.value
    }

    func playbackTracks(for selected: [Album]) async throws -> [Track] {
        if tracksLoaded { return try AlbumPlayback.assemble(albums: selected, tracks: index.tracks) }
        let local = selected.compactMap { details[$0.id] ?? localAlbum?($0.id) }
        if local.count == selected.count {
            return try AlbumPlayback.assemble(albums: selected, tracks: local.flatMap(\.normalizedTracks))
        }
        let loaded = try await requireTracks()
        return try AlbumPlayback.assemble(albums: selected, tracks: loaded)
    }

    func album(_ id: String, refresh: Bool = false) async throws -> Album {
        if (!refresh || offline), let album = cachedAlbum(id) { return album }
        if offline { throw ServerError(status: 404, code: nil) }
        let token = generation
        if let request = requests[id] {
            let album = try await request.value
            try Task.checkCancellation()
            guard token == generation else { throw CancellationError() }
            guard album.hidden != true || session.canSeeHidden else { throw ServerError(status: 404, code: nil) }
            return album
        }
        let session = session
        let request = Task { try await session.perform { try await $0.album(id) } }
        requests[id] = request
        defer { if token == generation { requests.removeValue(forKey: id) } }
        do {
            let album = try await request.value
            guard token == generation else { throw CancellationError() }
            guard album.hidden != true || session.canSeeHidden else { throw ServerError(status: 404, code: nil) }
            details[id] = album
            try? await disk?.save(scope + ":album:" + id, value: album)
            #if DEBUG
            await albumSnapshotBoundary?()
            #endif
            try Task.checkCancellation()
            guard token == generation else { throw CancellationError() }
            return album
        } catch {
            // Offline metadata is only available within the previously authorized
            // service and role. Authorization failures never fall back to disk.
            if token == generation, error is URLError {
                let saved = await disk?.load(scope + ":album:" + id, as: Album.self)
                #if DEBUG
                await albumSnapshotBoundary?()
                #endif
                try Task.checkCancellation()
                guard token == generation else { throw CancellationError() }
                if let saved, saved.hidden != true || session.canSeeHidden { return saved }
                if let local = localAlbum?(id), local.hidden != true || session.canSeeHidden { return local }
            }
            throw error
        }
    }

    func cachedAlbum(_ id: String) -> Album? {
        guard let album = details[id], album.hidden != true || session.canSeeHidden else { return nil }
        return album
    }

    // Administrator writes. The service is the source of truth: local copies
    // change only after it accepts the write, so a refusal leaves them intact.
    func save(_ id: String, edit: AlbumEdit) async throws {
        try await session.perform { try await $0.editAlbum(id, edit) }
        await invalidateAlbum(id)
    }

    func setHidden(_ id: String, hidden: Bool) async throws {
        try await session.perform { try await $0.hideAlbum(id, hidden: hidden) }
        if hidden && !showHidden { drop(id) }
        await invalidateAlbum(id)
    }

    func delete(_ id: String, files: Bool) async throws {
        try await session.perform { try await $0.deleteAlbum(id, files: files) }
        drop(id)
        // The refresh in invalidateAlbum also reloads favorites, which the service pruned.
        await invalidateAlbum(id)
    }

    private func drop(_ id: String) {
        albums.removeAll { $0.id == id }
        tracks.removeAll { $0.albumId == id }
        rebuildIndex()
    }

    func invalidateAlbum(_ id: String) async {
        details.removeValue(forKey: id)
        requests.removeValue(forKey: id)?.cancel()
        try? await disk?.remove(scope + ":album:" + id)
        albumETag = nil
        trackETag = nil
        await refresh()
        if tracksLoaded { await ensureTracks(force: true) }
    }

    func artist(_ name: String) -> Artist? { artists.first { $0.name == name } }

    func artistTracks(_ name: String) async throws -> [Track] {
        if offline { return [] }
        let token = generation
        let hidden = showHidden && session.canSeeHidden
        let tracks = try await session.perform { try await $0.featuredTracks(artist: name, includeHidden: hidden) }
        guard token == generation else { throw CancellationError() }
        return tracks
    }

    func biography(_ name: String) async throws -> String {
        if offline { return "" }
        let token = generation
        let text = try await session.perform { try await $0.biography(artist: name) }
        guard token == generation else { throw CancellationError() }
        return text
    }

    // A saved library stays usable when the service cannot be reached.
    private func describe(_ error: Error) -> String {
        if isUnreachable(error) && !albums.isEmpty { return L10n.text("mobile.offlineLibrary") }
        return error.localizedDescription
    }

    private func applyTracks(_ value: Versioned<[Track]>, generation token: UUID) async throws -> Bool {
        guard token == generation else { throw CancellationError() }
        // A validated unchanged response must not rebuild every search key or
        // invalidate the visible list when the user selects the Tracks tab.
        if tracksLoaded, let etag = value.etag, etag == trackETag { return false }
        while true {
            let before = revision
            let albums = albums, artists = artists
            let hidden = showHidden && session.canSeeHidden
            let next = await Task.detached(priority: .userInitiated) {
                CatalogIndex(albums: albums, tracks: value.value, artists: artists, includeHidden: hidden)
            }.value
            try Task.checkCancellation()
            guard token == generation else { throw CancellationError() }
            // An album edit can finish while indexing. Rebuild against its new
            // metadata instead of replacing it with an older snapshot.
            guard before == revision else { continue }
            tracks = value.value
            trackETag = value.etag
            tracksLoaded = true
            index = next
            revision = UUID()
            return true
        }
    }

    private func apply(_ value: CatalogSnapshot) {
        albums = value.albums; tracks = value.tracks ?? []; artists = value.artists
        tracksLoaded = value.tracks != nil
        albumETag = value.albumETag; trackETag = value.trackETag
        favorites.replace(value.favorites)
        rebuildIndex()
    }

    private func rebuildIndex() {
        revision = UUID()
        index = CatalogIndex(albums: albums, tracks: tracks, artists: artists,
            includeHidden: showHidden && session.canSeeHidden)
    }

    private func persist() async {
        let value = CatalogSnapshot(albums: albums, tracks: tracksLoaded ? tracks : nil, artists: artists,
            albumETag: albumETag, trackETag: trackETag, favorites: favorites.value)
        try? await disk?.save(scope, value: value)
    }
}
