import XCTest
@testable import Mihonban

// Hold real file operations at an explicit boundary to exercise session changes
// without slowing the main actor or replacing persistence with an in-memory fake.
private final class PersonalFavoritesFileGate: @unchecked Sendable {
    private let condition = NSCondition()
    private let heldReads: Set<Int>
    private let heldWrites: Set<Int>
    private var released = false
    private var failWrites = false
    private var reads = 0
    private var writes = 0
    private var active = 0
    private var peak = 0
    private var timedOut = false
    private var usedMainThread = false

    init(reads: Set<Int> = [], writes: Set<Int> = []) {
        heldReads = reads
        heldWrites = writes
    }

    var state: (reads: Int, writes: Int, peak: Int, timedOut: Bool, usedMainThread: Bool) {
        condition.lock()
        defer { condition.unlock() }
        return (reads, writes, peak, timedOut, usedMainThread)
    }

    func rejectWrites(_ value: Bool) {
        condition.lock()
        failWrites = value
        condition.unlock()
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }

    private func enter(write: Bool) -> Bool {
        condition.lock()
        if write { writes += 1 } else { reads += 1 }
        active += 1
        peak = max(peak, active)
        usedMainThread = usedMainThread || Thread.isMainThread
        let held = write ? heldWrites.contains(writes) : heldReads.contains(reads)
        let deadline = Date(timeIntervalSinceNow: 10)
        while held && !released {
            if !condition.wait(until: deadline) { timedOut = true; break }
        }
        let reject = write && failWrites
        condition.unlock()
        return reject
    }

    private func leave() {
        condition.lock()
        active -= 1
        condition.unlock()
    }

    func read(_ file: URL) throws -> PersonalFavoritesSnapshot {
        _ = enter(write: false)
        defer { leave() }
        return try PersonalFavoritesStorage.read(file)
    }

    func write(_ snapshot: PersonalFavoritesSnapshot, _ file: URL) throws {
        let reject = enter(write: true)
        defer { leave() }
        if reject { throw CocoaError(.fileWriteNoPermission) }
        try PersonalFavoritesStorage.write(snapshot, file)
    }
}

private final class PersonalFavoritesAppProtocol: URLProtocol {
    enum Mode: Sendable { case online, offline, rejected }
    final class State: @unchecked Sendable {
        struct Service {
            let library: Data
            let album: Data
            var mode: Mode = .online
            var requests: [URLRequest] = []
        }
        private let lock = NSLock()
        private var services: [String: Service] = [:]

        func register(_ host: String, album: Album) throws {
            var summary = album
            summary.tracks = nil
            let service = Service(library: try JSONEncoder().encode([summary]), album: try JSONEncoder().encode(album))
            lock.withLock { services[host] = service }
        }

        func mode(_ mode: Mode, host: String) { lock.withLock { services[host]?.mode = mode } }
        func remove(_ host: String) { _ = lock.withLock { services.removeValue(forKey: host) } }
        func requests(_ host: String) -> [URLRequest] { lock.withLock { services[host]?.requests ?? [] } }
        func response(_ request: URLRequest) -> Service? {
            lock.withLock {
                guard let host = request.url?.host else { return nil }
                services[host]?.requests.append(request)
                return services[host]
            }
        }
    }

    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasPrefix("personal-app-") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        guard let url = request.url, let service = Self.state.response(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        if service.mode == .offline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let data: Data
        let status: Int
        if service.mode == .rejected {
            data = Data(#"{"ok":false}"#.utf8)
            status = 401
        } else {
            status = 200
            switch url.lastPathComponent {
            case "login", "me": data = Data(#"{"ok":true,"role":"user","guest":false}"#.utf8)
            case "library": data = service.library
            case "saved-album": data = service.album
            case "favorites": data = Data(#"{"albums":[{"id":"curated-album"}],"tracks":[]}"#.utf8)
            default: data = Data("[]".utf8)
            }
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
private final class PersonalFavoritesAppFixture {
    let defaults: UserDefaults
    let api: APIClient
    let album = Album(id: "saved-album", title: "Saved album", artist: "Saved artist",
                      tracks: [Track(id: "saved-track", title: "Saved song", duration: 20, format: "mp3")])
    let root: URL
    let host: String
    private let suiteName: String
    private var models: [AppModel] = []

    init() throws {
        let id = UUID().uuidString.lowercased()
        host = "personal-app-" + id + ".invalid"
        suiteName = "org.mihonban.personal-app." + id
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        root = FileManager.default.temporaryDirectory.appendingPathComponent("personal-app-" + id)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PersonalFavoritesAppProtocol.self]
        configuration.httpCookieStorage = nil
        api = try APIClient(address: "https://" + host, session: URLSession(configuration: configuration))
        try PersonalFavoritesAppProtocol.state.register(host, album: album)
    }

    func model() -> AppModel {
        let value = AppModel(defaults: defaults, transport: api.session, artworkStore: ArtworkStore(), personalFavoritesRoot: root)
        value.player.setForeground(false)
        models.append(value)
        return value
    }

    func signIn() async -> AppModel {
        let value = model()
        value.address = api.baseURL.absoluteString
        value.password = "shared-listener-password"
        value.rememberPassword = false
        await value.connect()
        return value
    }

    func leavePreservingAuthorization(_ model: AppModel) {
        model.player.stop()
        model.downloads?.detach()
        model.personalFavorites.reset()
        model.catalog.reset()
        model.sessionStore.invalidate()
    }

    func cleanup() async {
        for model in models { model.disconnect(); model.player.setForeground(false) }
        let downloads = MediaPaths.downloads(service: MediaPaths.service(api.baseURL))
        _ = await DownloadManifestStorage.shared.load(directory: downloads)
        api.session.invalidateAndCancel()
        PersonalFavoritesAppProtocol.state.remove(host)
        defaults.removePersistentDomain(forName: suiteName)
        _ = CredentialStore.save(nil, for: api.baseURL.absoluteString)
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: MediaPaths.supportRoot.appendingPathComponent(MediaPaths.service(api.baseURL)))
        try? FileManager.default.removeItem(at: api.cacheDirectory)
    }
}

@MainActor
final class PersonalFavoritesTests: XCTestCase {
    private func root() -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent("personal-favorites-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: value) }
        return value
    }

    private let serviceA = URL(string: "https://personal-a.invalid/music")!
    private let serviceB = URL(string: "https://personal-b.invalid/music")!

    private func storage(_ gate: PersonalFavoritesFileGate) -> PersonalFavoritesStorage {
        PersonalFavoritesStorage(read: { try gate.read($0) }, write: { try gate.write($0, $1) })
    }

    private func waitForBoundary(_ condition: () -> Bool,
                                 file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Personal favorites did not reach the expected file boundary", file: file, line: line)
        throw CocoaError(.fileReadUnknown)
    }

    func testPersonalFavoritesPersistOfflineWithoutChangingSharedPicks() async throws {
        let directory = root()
        let store = PersonalFavoritesStore(root: directory)
        let session = SessionStore()
        session.connect(try APIClient(address: serviceA.absoluteString), info: SessionInfo(ok: true, role: "user", guest: false))
        let picks = FavoritesStore(session: session)
        picks.replace(Favorites(albums: [FavoriteItem(id: "curated-album")], tracks: [FavoriteItem(id: "curated-track")]))
        await store.connect(baseURL: serviceA)
        XCTAssertNil(store.error)
        XCTAssertTrue(store.isReady)
        let track = Track(id: "same-id", title: "Offline song", albumId: "same-id", albumTitle: "Offline album", artist: "Artist")
        let album = Album(id: "same-id", title: "Offline album", artist: "Artist", tracks: [track],
                          note: String(repeating: "Long note", count: 1_000), hidden: true,
                          folder: "private/folder", images: ["scan.png"])
        let initial = store.revision
        await store.toggle(album: album)
        await store.toggle(track: track)
        XCTAssertNotEqual(store.revision, initial)
        XCTAssertTrue(store.contains(.album, id: "same-id"))
        XCTAssertTrue(store.contains(.track, id: "same-id"), "Album and track IDs have independent namespaces")
        XCTAssertEqual(picks.value.albums.map(\.id), ["curated-album"])
        XCTAssertEqual(picks.value.tracks.map(\.id), ["curated-track"])
        XCTAssertNil(store.albums.first?.tracks)
        XCTAssertNil(store.albums.first?.note)
        XCTAssertNil(store.albums.first?.images)
        XCTAssertNil(store.albums.first?.folder)
        XCTAssertEqual(store.albums.first?.hidden, true, "Visibility metadata must survive snapshot compaction")
        store.reset()
        XCTAssertTrue(store.albums.isEmpty && store.tracks.isEmpty)
        XCTAssertFalse(store.isReady)
        await store.toggle(track: Track(id: "signed-out", title: "Must not save"))
        let reopened = PersonalFavoritesStore(root: directory)
        await reopened.connect(baseURL: serviceA)
        XCTAssertEqual(reopened.albums.map(\.title), ["Offline album"])
        XCTAssertEqual(reopened.tracks, [track], "A track saved from an album page needs no all-tracks network request to reload")
        XCTAssertFalse(reopened.contains(.track, id: "signed-out"))
        XCTAssertNil(reopened.error)
    }

    func testPersonalFavoritesKeepServicesAndBasePathsSeparate() async throws {
        let directory = root()
        let store = PersonalFavoritesStore(root: directory)
        let services = [serviceA, serviceB, URL(string: "https://personal-a.invalid/other")!,
                        URL(string: "http://personal-a.invalid/music")!, URL(string: "https://personal-a.invalid:8443/music")!]
        for (index, service) in services.enumerated() {
            await store.connect(baseURL: service)
            XCTAssertTrue(store.tracks.isEmpty)
            await store.toggle(track: Track(id: "same-id", title: "Service \(index)", albumId: "album"))
        }
        for (index, service) in services.enumerated() {
            await store.connect(baseURL: service)
            XCTAssertEqual(store.tracks.map(\.title), ["Service \(index)"])
        }
        await store.connect(baseURL: URL(string: "https://PERSONAL-A.invalid/music/?unused=1#fragment")!)
        XCTAssertEqual(store.tracks.map(\.title), ["Service 0"], "Equivalent normalized service addresses reuse their saved collection")
    }

    func testPersonalFavoritesReorderAndRemovalPreserveOtherKinds() async throws {
        let directory = root()
        let store = PersonalFavoritesStore(root: directory)
        await store.connect(baseURL: serviceA)
        await store.toggle(album: Album(id: "album", title: "Album", artist: "Artist"))
        for id in ["one", "two", "three"] { await store.toggle(track: Track(id: id, title: id)) }
        XCTAssertEqual(store.tracks.map(\.id), ["three", "two", "one"])
        await store.reorder(.track, ids: ["one", "two"])
        await store.reorder(.track, ids: ["one", "one", "three"])
        XCTAssertEqual(store.tracks.map(\.id), ["three", "two", "one"], "A partial or duplicated projection cannot discard stored items")
        await store.reorder(.track, ids: ["one", "three", "two"])
        await store.remove(.track, ids: ["three", "missing", "three"])
        let reopened = PersonalFavoritesStore(root: directory)
        await reopened.connect(baseURL: serviceA)
        XCTAssertEqual(reopened.tracks.map(\.id), ["one", "two"])
        XCTAssertEqual(reopened.albums.map(\.id), ["album"])
        await reopened.toggle(track: Track(id: "one", title: "Different title"))
        XCTAssertEqual(reopened.tracks.map(\.id), ["two"], "Toggle removes by identity, not by stale metadata")
    }

    func testPersonalFavoritesFailedWriteKeepsPersistedStateAndReportsError() async throws {
        let directory = root()
        let gate = PersonalFavoritesFileGate()
        let io = storage(gate)
        let store = PersonalFavoritesStore(root: directory, storage: io)
        await store.connect(baseURL: serviceA)
        await store.toggle(track: Track(id: "kept", title: "Kept"))
        let revision = store.revision
        gate.rejectWrites(true)
        await store.remove(.track, ids: ["kept"])
        XCTAssertTrue(store.contains(.track, id: "kept"))
        XCTAssertEqual(store.revision, revision)
        XCTAssertEqual(store.error, L10n.text("personal.saveFailed"))
        XCTAssertFalse(store.busy)
        await store.toggle(track: Track(id: "failed", title: "Not saved"))
        XCTAssertFalse(store.contains(.track, id: "failed"))
        let reopened = PersonalFavoritesStore(root: directory, storage: io)
        await reopened.connect(baseURL: serviceA)
        XCTAssertEqual(reopened.tracks.map(\.id), ["kept"])
        gate.rejectWrites(false)
        await store.toggle(track: Track(id: "retry", title: "Retry"))
        XCTAssertNil(store.error)
        XCTAssertEqual(store.tracks.map(\.id), ["retry", "kept"])
        XCTAssertFalse(gate.state.usedMainThread, "Encoding, decoding and filesystem work must remain off the main thread")
    }

    func testPersonalFavoritesCorruptLoadCannotBeOverwrittenByAnEmptyState() async throws {
        let directory = root()
        let target = try PersonalFavoritesStore.fileURL(root: directory, baseURL: serviceA)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("unfinished json".utf8)
        try corrupt.write(to: target)
        let store = PersonalFavoritesStore(root: directory)
        await store.connect(baseURL: serviceA)
        XCTAssertEqual(store.error, L10n.text("personal.loadFailed"))
        XCTAssertFalse(store.loading)
        XCTAssertFalse(store.isReady)
        await store.toggle(track: Track(id: "new", title: "Must wait for recovery"))
        XCTAssertTrue(store.tracks.isEmpty)
        XCTAssertEqual(try Data(contentsOf: target), corrupt, "A failed read must not silently destroy an existing collection")
    }

    func testPersonalFavoritesLateReadCannotPublishAcrossServiceSwitch() async throws {
        let directory = root()
        let target = try PersonalFavoritesStore.fileURL(root: directory, baseURL: serviceA)
        try PersonalFavoritesStorage.write(PersonalFavoritesSnapshot(tracks: [Track(id: "old", title: "Old service")]), target)
        let gate = PersonalFavoritesFileGate(reads: [1])
        defer { gate.release() }
        let store = PersonalFavoritesStore(root: directory, storage: storage(gate))
        let old = Task { await store.connect(baseURL: serviceA) }
        addTeardownBlock { gate.release(); await old.value }
        try await waitForBoundary { gate.state.reads == 1 }
        await store.connect(baseURL: serviceB)
        await store.toggle(track: Track(id: "new", title: "New service"))
        let revision = store.revision
        gate.release()
        await old.value
        XCTAssertEqual(store.tracks.map(\.id), ["new"])
        XCTAssertEqual(store.revision, revision)
        XCTAssertNil(store.error)
        XCTAssertFalse(store.loading)
        XCTAssertFalse(gate.state.timedOut)
    }

    func testPersonalFavoritesLateWriteCannotPublishAfterResetOrServiceSwitch() async throws {
        let directory = root()
        let gate = PersonalFavoritesFileGate(writes: [1])
        defer { gate.release() }
        let io = storage(gate)
        let store = PersonalFavoritesStore(root: directory, storage: io)
        await store.connect(baseURL: serviceA)
        let old = Task { await store.toggle(track: Track(id: "old", title: "Old service")) }
        addTeardownBlock { gate.release(); await old.value }
        try await waitForBoundary { gate.state.writes == 1 }
        XCTAssertTrue(store.busy)
        XCTAssertFalse(store.contains(.track, id: "old"), "The pending disk write is not reported as persisted")
        await store.toggle(track: Track(id: "double-tap", title: "Ignored while busy"))
        XCTAssertEqual(gate.state.writes, 1)
        store.reset()
        XCTAssertFalse(store.busy)
        await store.connect(baseURL: serviceB)
        await store.toggle(track: Track(id: "new", title: "New service"))
        let revision = store.revision
        gate.release()
        await old.value
        XCTAssertEqual(store.tracks.map(\.id), ["new"])
        XCTAssertEqual(store.revision, revision)
        XCTAssertNil(store.error)
        let reopened = PersonalFavoritesStore(root: directory, storage: io)
        await reopened.connect(baseURL: serviceA)
        XCTAssertEqual(reopened.tracks.map(\.id), ["old"], "The accepted old-service write may finish only in its original file")
        XCTAssertFalse(gate.state.timedOut)
    }

    func testPersonalFavoritesReopeningSameServiceWaitsForPendingWrite() async throws {
        let directory = root()
        let gate = PersonalFavoritesFileGate(writes: [1])
        defer { gate.release() }
        let io = storage(gate)
        let oldStore = PersonalFavoritesStore(root: directory, storage: io)
        await oldStore.connect(baseURL: serviceA)
        let write = Task { await oldStore.toggle(track: Track(id: "saved", title: "Saved before leaving")) }
        addTeardownBlock { gate.release(); await write.value }
        try await waitForBoundary { gate.state.writes == 1 }
        oldStore.reset()
        let replacement = PersonalFavoritesStore(root: directory, storage: io)
        var started = false
        var checking = true
        let premature = expectation(description: "Reopening must await the previous atomic replacement")
        premature.isInverted = true
        let load = Task {
            started = true
            await replacement.connect(baseURL: serviceA)
            if checking { premature.fulfill() }
        }
        addTeardownBlock { gate.release(); await load.value }
        try await waitForBoundary { started }
        await fulfillment(of: [premature], timeout: 0.2)
        checking = false
        XCTAssertTrue(replacement.loading)
        XCTAssertEqual(gate.state.reads, 1, "The new read cannot enter while the earlier write is held")
        gate.release()
        await write.value
        await load.value
        XCTAssertEqual(replacement.tracks.map(\.id), ["saved"])
        XCTAssertTrue(oldStore.tracks.isEmpty, "A retired operation cannot revive the old store")
        XCTAssertFalse(replacement.loading)
        XCTAssertFalse(replacement.busy)
        XCTAssertEqual(gate.state.peak, 1, "Reads and writes for one file must not overlap")
        XCTAssertFalse(gate.state.usedMainThread)
        XCTAssertFalse(gate.state.timedOut)
    }

    func testPersonalProjectionHidesNormalizedTracksWithHiddenParentsWithoutPruningBookmarks() async throws {
        let directory = root()
        let store = PersonalFavoritesStore(root: directory)
        await store.connect(baseURL: serviceA)
        let album = Album(id: "hidden-album", title: "Private album", artist: "Artist",
                          tracks: [Track(id: "hidden-song", title: "Private song")], hidden: true)
        let track = try XCTUnwrap(album.normalizedTracks.first)
        XCTAssertNil(track.hidden, "Album-normalized tracks do not inherit the parent hidden flag")
        await store.toggle(album: album)
        await store.toggle(track: track)
        let visibleIndex = CatalogIndex(albums: [album], tracks: [track], artists: [], includeHidden: false)
        XCTAssertEqual(visibleIndex.tracks.count, 1, "The projection must also validate the track's parent")
        for loaded in [false, true] {
            let hidden = PersonalFavoritesProjection.build(albums: store.albums, tracks: store.tracks,
                index: visibleIndex, tracksLoaded: loaded, includeHidden: false)
            XCTAssertTrue(hidden.albums.isEmpty && hidden.tracks.isEmpty)
        }
        let allowedIndex = CatalogIndex(albums: [album], tracks: [track], artists: [], includeHidden: true)
        let downgraded = PersonalFavoritesProjection.build(albums: store.albums, tracks: store.tracks,
            index: allowedIndex, tracksLoaded: true, includeHidden: false)
        XCTAssertTrue(downgraded.albums.isEmpty && downgraded.tracks.isEmpty,
                      "A role downgrade must hide old privileged index entries before the next catalog refresh")
        let allowed = PersonalFavoritesProjection.build(albums: store.albums, tracks: store.tracks,
            index: allowedIndex, tracksLoaded: true, includeHidden: true)
        XCTAssertEqual(allowed.albums.map(\.id), [album.id])
        XCTAssertEqual(allowed.tracks.map(\.id), [track.id])
        store.reset()
        await store.connect(baseURL: serviceA)
        XCTAssertEqual(store.albums.map(\.id), [album.id])
        XCTAssertEqual(store.tracks.map(\.id), [track.id], "Hiding or temporarily missing catalog items must not erase saved IDs")
    }

    func testPersonalProjectionUsesCurrentMetadataAndDoesNotReviveRemovedTracks() {
        let album = Album(id: "album", title: "Current album", artist: "Current artist")
        let staleAlbum = Album(id: "album", title: "Old title", artist: "Old artist")
        let stale = Track(id: "live", title: "Old song title", albumId: "album")
        let current = Track(id: "live", title: "Renamed song", albumId: "album")
        let removed = Track(id: "removed", title: "Removed song", albumId: "album")
        let index = CatalogIndex(albums: [album], tracks: [current], artists: [], includeHidden: false)
        let projection = PersonalFavoritesProjection.build(albums: [staleAlbum], tracks: [removed, stale],
            index: index, tracksLoaded: true, includeHidden: false)
        XCTAssertEqual(projection.albums, [album])
        XCTAssertEqual(projection.tracks, [current], "A completed catalog is authoritative even if an old local snapshot exists")
        var nowHidden = current
        nowHidden.hidden = true
        let privilegedIndex = CatalogIndex(albums: [album], tracks: [nowHidden], artists: [], includeHidden: true)
        for loaded in [false, true] {
            let downgraded = PersonalFavoritesProjection.build(albums: [staleAlbum], tracks: [stale],
                index: privilegedIndex, tracksLoaded: loaded, includeHidden: false)
            XCTAssertEqual(downgraded.albums, [album], "A visible parent remains available after a role downgrade")
            XCTAssertTrue(downgraded.tracks.isEmpty,
                          "A hidden current track cannot fall back to its older visible snapshot while the privileged index remains")
        }
        let authorized = PersonalFavoritesProjection.build(albums: [], tracks: [stale],
            index: privilegedIndex, tracksLoaded: false, includeHidden: true)
        XCTAssertEqual(authorized.tracks, [nowHidden], "Authorized hidden browsing must still use current metadata")
    }

    func testPersonalProjectionUsesOfflineSnapshotsOnlyForAuthorizedParentsBeforeTracksLoad() {
        let album = Album(id: "allowed", title: "Allowed album", artist: "Artist")
        let saved = Track(id: "saved", title: "Saved song", albumId: album.id)
        let hidden = Track(id: "hidden", title: "Hidden song", albumId: album.id, hidden: true)
        let absent = Track(id: "other-service", title: "Must not appear", albumId: "absent")
        let orphan = Track(id: "orphan", title: "No parent")
        let index = CatalogIndex(albums: [album], tracks: [], artists: [], includeHidden: false)
        let projection = PersonalFavoritesProjection.build(albums: [], tracks: [saved, hidden, absent, orphan],
            index: index, tracksLoaded: false, includeHidden: false)
        XCTAssertEqual(projection.tracks, [saved])
        let loaded = PersonalFavoritesProjection.build(albums: [], tracks: [saved, hidden, absent, orphan],
            index: index, tracksLoaded: true, includeHidden: false)
        XCTAssertTrue(loaded.tracks.isEmpty)
    }

    func testPersonalFavoritesAppOfflineRelaunchCacheClearLogoutAndReauthorization() async throws {
        let fixture = try PersonalFavoritesAppFixture()
        addTeardownBlock { await fixture.cleanup() }
        let online = await fixture.signIn()
        XCTAssertTrue(online.signedIn)
        XCTAssertEqual(online.session?.role, "user")
        XCTAssertTrue(online.personalFavorites.isReady)
        XCTAssertFalse(online.catalog.tracksLoaded)
        let album = try await online.album(fixture.album.id)
        let track = try XCTUnwrap(album.normalizedTracks.first)
        let beforePersonalActions = PersonalFavoritesAppProtocol.state.requests(fixture.host).count
        await online.personalFavorites.toggle(album: album)
        await online.personalFavorites.toggle(track: track)
        XCTAssertEqual(PersonalFavoritesAppProtocol.state.requests(fixture.host).count, beforePersonalActions,
                       "Ordinary listener favorites are local and must not call any server endpoint")
        XCTAssertEqual(online.favorites.value.albums.map(\.id), ["curated-album"])
        XCTAssertTrue(online.favorites.value.tracks.isEmpty)
        let savedFile = try PersonalFavoritesStore.fileURL(root: fixture.root, baseURL: fixture.api.baseURL)
        let savedBytes = try Data(contentsOf: savedFile)
        let cleared = await online.clearCache()
        XCTAssertTrue(cleared)
        XCTAssertEqual(try Data(contentsOf: savedFile), savedBytes, "Clear cache cannot erase the personal collection")
        fixture.leavePreservingAuthorization(online)
        PersonalFavoritesAppProtocol.state.mode(.offline, host: fixture.host)
        let offline = fixture.model()
        await offline.bootstrap()
        XCTAssertTrue(offline.signedIn)
        XCTAssertTrue(offline.personalFavorites.isReady)
        XCTAssertNil(offline.personalFavorites.error)
        XCTAssertFalse(offline.catalog.tracksLoaded)
        let projection = PersonalFavoritesProjection.build(albums: offline.personalFavorites.albums,
            tracks: offline.personalFavorites.tracks, index: offline.catalog.index,
            tracksLoaded: offline.catalog.tracksLoaded, includeHidden: false)
        XCTAssertEqual(projection.albums.map(\.id), [album.id])
        XCTAssertEqual(projection.tracks, [track])
        offline.disconnect()
        XCTAssertFalse(offline.personalFavorites.isReady)
        XCTAssertTrue(offline.personalFavorites.albums.isEmpty && offline.personalFavorites.tracks.isEmpty)
        XCTAssertNil(RememberedSession.load(fixture.defaults))
        XCTAssertEqual(try Data(contentsOf: savedFile), savedBytes, "Signing out hides the collection while preserving it for later authorization")
        let signedOut = fixture.model()
        await signedOut.bootstrap()
        XCTAssertFalse(signedOut.signedIn)
        XCTAssertFalse(signedOut.personalFavorites.isReady)
        XCTAssertTrue(signedOut.personalFavorites.tracks.isEmpty)
        PersonalFavoritesAppProtocol.state.mode(.online, host: fixture.host)
        let reauthorized = await fixture.signIn()
        XCTAssertTrue(reauthorized.signedIn)
        XCTAssertEqual(reauthorized.personalFavorites.tracks, [track])
        let writes = PersonalFavoritesAppProtocol.state.requests(fixture.host).filter { ($0.httpMethod ?? "GET") != "GET" }
        XCTAssertEqual(writes.count, 2)
        XCTAssertTrue(writes.allSatisfy { $0.httpMethod == "POST" && $0.url?.lastPathComponent == "login" },
                      "Only explicit sign-ins may write to the fixture; personal actions never alter administrator picks")
    }

    func testPersonalFavoritesAppRejectedAuthorizationNeverLoadsLocalBookmarks() async throws {
        let fixture = try PersonalFavoritesAppFixture()
        addTeardownBlock { await fixture.cleanup() }
        let online = await fixture.signIn()
        let album = try await online.album(fixture.album.id)
        await online.personalFavorites.toggle(track: try XCTUnwrap(album.normalizedTracks.first))
        fixture.leavePreservingAuthorization(online)
        PersonalFavoritesAppProtocol.state.mode(.rejected, host: fixture.host)
        let rejected = fixture.model()
        await rejected.bootstrap()
        XCTAssertFalse(rejected.signedIn)
        XCTAssertFalse(rejected.personalFavorites.isReady)
        XCTAssertTrue(rejected.personalFavorites.tracks.isEmpty)
        XCTAssertNil(RememberedSession.load(fixture.defaults))
        PersonalFavoritesAppProtocol.state.mode(.offline, host: fixture.host)
        let offline = fixture.model()
        await offline.bootstrap()
        XCTAssertFalse(offline.signedIn)
        XCTAssertFalse(offline.personalFavorites.isReady)
        XCTAssertTrue(offline.personalFavorites.tracks.isEmpty, "A refused authorization cannot be revived by an offline startup")
        let stored = PersonalFavoritesStore(root: fixture.root)
        await stored.connect(baseURL: fixture.api.baseURL)
        XCTAssertEqual(stored.tracks.map(\.id), ["saved-track"], "Refusal revokes access without deleting the user's local bookmarks")
    }

    func testPersonalFavoritesAppRuntimeRejectionRetiresPendingUIActionsWithoutDeletingBookmarks() async throws {
        let fixture = try PersonalFavoritesAppFixture()
        addTeardownBlock { await fixture.cleanup() }
        let model = await fixture.signIn()
        let album = try await model.album(fixture.album.id)
        let track = try XCTUnwrap(album.normalizedTracks.first)
        await model.personalFavorites.toggle(track: track)
        let revisionBeforeRefusal = model.personalFavorites.revision
        let file = try PersonalFavoritesStore.fileURL(root: fixture.root, baseURL: fixture.api.baseURL)
        let saved = try Data(contentsOf: file)
        PersonalFavoritesAppProtocol.state.mode(.rejected, host: fixture.host)
        await model.refresh()
        XCTAssertFalse(model.signedIn)
        XCTAssertTrue(model.sessionStore.needsSignIn)
        XCTAssertFalse(model.personalFavorites.isReady)
        XCTAssertTrue(model.personalFavorites.albums.isEmpty && model.personalFavorites.tracks.isEmpty)
        XCTAssertNotEqual(model.personalFavorites.revision, revisionBeforeRefusal,
                          "A UI action captured before rejection must fail its collection revision guard")
        XCTAssertNil(RememberedSession.load(fixture.defaults))
        await model.personalFavorites.toggle(track: Track(id: "late-tap", title: "Must not persist", albumId: album.id))
        await model.personalFavorites.remove(.track, ids: [track.id])
        XCTAssertEqual(try Data(contentsOf: file), saved, "Retired local controls cannot modify the saved collection after rejection")
        let requests = PersonalFavoritesAppProtocol.state.requests(fixture.host)
        XCTAssertTrue(requests.filter { ($0.httpMethod ?? "GET") != "GET" }.allSatisfy { $0.url?.lastPathComponent == "login" })
    }
}
