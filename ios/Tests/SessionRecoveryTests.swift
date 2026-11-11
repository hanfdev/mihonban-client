import XCTest
@testable import Mihonban

private final class SessionRecoveryProtocol: URLProtocol {
    enum Reply {
        case response(Int, String)
        case failure(URLError.Code)
        case held
    }

    final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [String: [String: [Reply]]] = [:]
        private var counts: [String: [String: Int]] = [:]
        private var pending: [String: [String: [SessionRecoveryProtocol]]] = [:]

        func configure(_ host: String, replies: [String: [Reply]]) {
            lock.withLock { self.replies[host] = replies }
        }

        func take(_ connection: SessionRecoveryProtocol) -> Reply {
            let host = connection.request.url!.host!
            let path = connection.request.url!.lastPathComponent
            return lock.withLock {
                counts[host, default: [:]][path, default: 0] += 1
                guard var queue = replies[host]?[path], !queue.isEmpty else {
                    return .response(500, "{}")
                }
                let reply = queue.removeFirst()
                replies[host]?[path] = queue
                if case .held = reply { pending[host, default: [:]][path, default: []].append(connection) }
                return reply
            }
        }

        func count(_ host: String, _ path: String) -> Int {
            lock.withLock { counts[host]?[path] ?? 0 }
        }

        func recordInvocation(_ host: String) {
            lock.withLock { counts[host, default: [:]]["operation", default: 0] += 1 }
        }

        func release(_ host: String, _ path: String, reply: Reply) {
            let connections = lock.withLock { () -> [SessionRecoveryProtocol] in
                let values = pending[host]?[path] ?? []
                pending[host]?[path] = nil
                return values
            }
            for connection in connections { connection.finish(reply) }
        }

        func remove(_ host: String) {
            lock.withLock {
                replies[host] = nil
                counts[host] = nil
                pending[host] = nil
            }
        }
    }

    static let gate = Gate()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { finish(Self.gate.take(self)) }
    override func stopLoading() {}

    private func finish(_ reply: Reply) {
        switch reply {
        case .response(let status, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code): client?.urlProtocol(self, didFailWithError: URLError(code))
        case .held: break
        }
    }
}

@MainActor
private final class AuthorizationRenewalFixture {
    let model: AppModel
    let api: APIClient
    let defaults: UserDefaults
    let host: String
    let personalRoot: URL
    let catalogRoot: URL
    let visible = Album(id: "visible", title: "Public album", artist: "Public artist")
    let hidden = Album(id: "hidden", title: "Private album", artist: "Private artist", hidden: true)
    let privateTrack = Track(id: "private-track", title: "Private song", duration: 30, format: "flac",
                             albumId: "hidden", albumTitle: "Private album", artist: "Private artist", hidden: true)
    private let suiteName: String

    init(role: String) throws {
        let identity = UUID().uuidString.lowercased()
        host = "session-role-" + identity + ".invalid"
        suiteName = "org.mihonban.session-role." + identity
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        personalRoot = FileManager.default.temporaryDirectory.appendingPathComponent("session-role-" + identity)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionRecoveryProtocol.self]
        configuration.httpCookieStorage = nil
        api = try APIClient(address: "https://" + host, session: URLSession(configuration: configuration))
        catalogRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mihonban/" + digest(api.baseURL.absoluteString) + "/catalog", isDirectory: true)
        model = AppModel(defaults: defaults, transport: api.session, artworkStore: ArtworkStore(),
                         personalFavoritesRoot: personalRoot)
        model.player.setForeground(false)
        model.address = api.baseURL.absoluteString
        defaults.set(model.address, forKey: "serviceAddress")
        RememberedSession.save(RememberedSession(address: model.address, role: role, guest: false), defaults)
        model.sessionStore.connect(api, info: SessionInfo(ok: true, role: role, guest: false))
        XCTAssertTrue(CredentialStore.save("role-password", for: api.baseURL.absoluteString))
    }

    private func json<Value: Encodable>(_ value: Value) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    func prepare() async throws {
        SessionRecoveryProtocol.gate.configure(host, replies: [
            "library": [.response(200, try json([visible])), .response(200, try json([visible, hidden]))],
            "artists": [.response(200, "[]"), .response(200, "[]")],
            "favorites": [.response(200, #"{"albums":[],"tracks":[]}"#),
                          .response(200, #"{"albums":[],"tracks":[]}"#)],
            "tracks": [.response(200, try json([privateTrack]))],
            hidden.id: [.response(200, try json(hidden))],
        ])
        await model.catalog.connect()
        await model.catalog.setShowHidden(true)
        _ = try await model.catalog.requireTracks()
        _ = try await model.catalog.album(hidden.id)
        await model.personalFavorites.connect(baseURL: api.baseURL)
        await model.personalFavorites.toggle(track: privateTrack)
        XCTAssertEqual(Set(model.catalog.index.albums.map(\.id)), [visible.id, hidden.id])
        XCTAssertEqual(model.catalog.index.tracks.map(\.id), [privateTrack.id])
        XCTAssertNotNil(model.catalog.cachedAlbum(hidden.id))
        XCTAssertTrue(model.personalFavorites.contains(.track, id: privateTrack.id))
    }

    func renewAs(_ role: String, holdRefresh: Bool) {
        let empty = #"{"albums":[],"tracks":[]}"#
        SessionRecoveryProtocol.gate.configure(host, replies: [
            "login": [.response(200, "{\"ok\":true,\"role\":\"" + role + "\",\"guest\":false}")],
            "favorites": [.response(401, "{}"), .response(200, empty), .response(200, empty)],
            "library": holdRefresh ? [.held] : [],
            "artists": holdRefresh ? [.held] : [],
            "tracks": holdRefresh ? [.held] : [],
        ])
    }

    func releaseRefresh() {
        for path in ["library", "artists", "tracks"] {
            SessionRecoveryProtocol.gate.release(host, path, reply: .response(200, "[]"))
        }
    }

    func cleanup() {
        model.sessionStore.authorizationChanged = nil
        model.disconnect()
        model.player.setForeground(false)
        releaseRefresh()
        api.session.invalidateAndCancel()
        SessionRecoveryProtocol.gate.remove(host)
        defaults.removePersistentDomain(forName: suiteName)
        _ = CredentialStore.save(nil, for: api.baseURL.absoluteString)
        try? FileManager.default.removeItem(at: personalRoot)
        try? FileManager.default.removeItem(at: catalogRoot)
        try? FileManager.default.removeItem(at: api.cacheDirectory)
    }
}

@MainActor
extension OfflineLaunchTests {
    private var success: String { #"{"ok":true,"role":"admin","guest":false}"# }

    private func fixture(password: Bool = true, login: [SessionRecoveryProtocol.Reply],
                         requests: [SessionRecoveryProtocol.Reply]) throws -> (SessionStore, APIClient, String) {
        let host = "session-\(UUID().uuidString.lowercased()).invalid"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionRecoveryProtocol.self]
        let transport = URLSession(configuration: configuration)
        let api = try APIClient(address: "https://" + host, session: transport)
        SessionRecoveryProtocol.gate.configure(host, replies: ["login": login, "favorites": requests])
        addTeardownBlock {
            transport.invalidateAndCancel()
            SessionRecoveryProtocol.gate.remove(host)
            await MainActor.run { _ = CredentialStore.save(nil, for: api.baseURL.absoluteString) }
        }
        XCTAssertTrue(CredentialStore.save(password ? "test-password" : nil, for: api.baseURL.absoluteString))
        XCTAssertEqual(CredentialStore.read(for: api.baseURL.absoluteString), password ? "test-password" : nil)
        let session = SessionStore()
        session.connect(api, info: SessionInfo(ok: true, role: "user", guest: false))
        return (session, api, host)
    }

    private func failure(_ session: SessionStore) async -> Error? {
        do {
            _ = try await session.perform { try await $0.favorites() }
            XCTFail("The scripted request should fail")
            return nil
        } catch { return error }
    }

    private func waitForRequests(_ host: String, _ path: String, count: Int) async throws {
        for _ in 0..<200 {
            if SessionRecoveryProtocol.gate.count(host, path) == count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The expected request did not reach the transport")
        throw URLError(.timedOut)
    }

    func testSuccessfulRenewalKeepsAuthorizationWhenRetriedRequestFailsForOtherReasons() async throws {
        for reply: SessionRecoveryProtocol.Reply in [.failure(.timedOut), .response(500, "{}"), .response(403, "{}")] {
            let (session, _, host) = try fixture(login: [.response(200, success)],
                requests: [.response(401, "{}"), reply])
            var rejected: [URL] = []
            session.authorizationRejected = { rejected.append($0) }
            let error = await failure(session)
            XCTAssertNotNil(error)
            XCTAssertEqual(SessionRecoveryProtocol.gate.count(host, "login"), 1)
            XCTAssertEqual(SessionRecoveryProtocol.gate.count(host, "favorites"), 2)
            XCTAssertEqual(session.info?.role, "admin")
            XCTAssertFalse(session.needsSignIn, "A timeout, server failure or resource permission error is not a login refusal")
            XCTAssertTrue(rejected.isEmpty)
        }
    }

    func testTransientOrCancelledRenewalDoesNotForgetAuthorization() async throws {
        for reply: SessionRecoveryProtocol.Reply in [.failure(.timedOut), .response(503, "{}"), .failure(.cancelled)] {
            let (session, _, host) = try fixture(login: [reply], requests: [.response(401, "{}")])
            var rejected: [URL] = []
            session.authorizationRejected = { rejected.append($0) }
            let error = await failure(session)
            XCTAssertNotNil(error)
            if case .failure(.cancelled) = reply { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(SessionRecoveryProtocol.gate.count(host, "favorites"), 1, "Failed renewal must not retry the operation")
            XCTAssertFalse(session.needsSignIn)
            XCTAssertTrue(rejected.isEmpty)
        }
    }

    func testMissingCredentialsAndRejectedLoginNotifyOnceForTheActiveService() async throws {
        for password in [false, true] {
            let (session, api, host) = try fixture(password: password,
                login: [.response(401, "{}"), .response(401, "{}")],
                requests: [.response(401, "{}"), .response(401, "{}")])
            var rejected: [URL] = []
            session.authorizationRejected = { rejected.append($0) }
            let firstError = await failure(session)
            let secondError = await failure(session)
            XCTAssertNotNil(firstError)
            XCTAssertNotNil(secondError)
            XCTAssertTrue(session.needsSignIn)
            XCTAssertEqual(rejected, [api.baseURL])
            XCTAssertEqual(SessionRecoveryProtocol.gate.count(host, "login"), password ? 2 : 0)
        }
    }

    func testConcurrentRequestsShareRenewalAndRejectAnInvalidRenewedSession() async throws {
        let (session, api, host) = try fixture(login: [.held],
            requests: [.response(401, "{}"), .response(401, "{}")])
        var rejected: [URL] = []
        session.authorizationRejected = { rejected.append($0) }
        let first = Task { await failure(session) }
        let second = Task { await failure(session) }
        defer { first.cancel(); second.cancel() }
        try await waitForRequests(host, "favorites", count: 2)
        try await waitForRequests(host, "login", count: 1)
        SessionRecoveryProtocol.gate.release(host, "login", reply: .response(200, #"{"ok":false}"#))
        let firstError = await first.value
        let secondError = await second.value
        XCTAssertNotNil(firstError)
        XCTAssertNotNil(secondError)
        XCTAssertEqual(SessionRecoveryProtocol.gate.count(host, "login"), 1)
        XCTAssertEqual(SessionRecoveryProtocol.gate.count(host, "favorites"), 2, "Neither waiter retries after invalid renewal")
        XCTAssertTrue(session.needsSignIn)
        XCTAssertEqual(rejected, [api.baseURL])
    }

    func testRetriedUnauthorizedRequestRejectsTheRenewedSession() async throws {
        let (session, api, host) = try fixture(login: [.response(200, success)],
            requests: [.response(401, "{}"), .response(401, "{}")])
        var rejected: [URL] = []
        session.authorizationRejected = { rejected.append($0) }
        let error = await failure(session)
        XCTAssertEqual((error as? ServerError)?.status, 401)
        XCTAssertEqual(SessionRecoveryProtocol.gate.count(host, "login"), 1)
        XCTAssertTrue(session.needsSignIn)
        XCTAssertEqual(rejected, [api.baseURL])
    }

    func testLateUnauthorizedResponseCannotRejectAReplacementSession() async throws {
        let (session, original, host) = try fixture(password: false, login: [], requests: [.held])
        var rejected: [URL] = []
        session.authorizationRejected = { rejected.append($0) }
        let request = Task { await failure(session) }
        defer { request.cancel() }
        try await waitForRequests(host, "favorites", count: 1)
        let replacement = try APIClient(address: "https://replacement.invalid", session: original.session)
        session.connect(replacement, info: SessionInfo(ok: true, role: "admin", guest: false))
        SessionRecoveryProtocol.gate.release(host, "favorites", reply: .response(401, "{}"))
        let error = await request.value
        XCTAssertTrue(error is CancellationError)
        XCTAssertEqual(session.client?.baseURL, replacement.baseURL)
        XCTAssertEqual(session.info?.role, "admin")
        XCTAssertFalse(session.needsSignIn)
        XCTAssertTrue(rejected.isEmpty)
        XCTAssertEqual(SessionRecoveryProtocol.gate.count(host, "login"), 0)
    }

    func testConcurrentSuccessfulRenewalNotifiesAuthorizationChangeOnce() async throws {
        for (role, guest) in [("user", false), ("admin", true)] {
            let empty = #"{"albums":[],"tracks":[]}"#
            let (session, api, host) = try fixture(login: [.held], requests: [
                .response(401, "{}"), .response(401, "{}"), .response(200, empty), .response(200, empty),
            ])
            session.connect(api, info: SessionInfo(ok: true, role: "admin", guest: false))
            let sessionRevision = session.revision
            let authorizationRevision = session.authorizationRevision
            var notifications = 0
            var observedRole: String?
            var observedGuest: Bool?
            var observedRevision: UUID?
            session.authorizationChanged = {
                notifications += 1
                observedRole = session.info?.role
                observedGuest = session.info?.guest
                observedRevision = session.authorizationRevision
            }
            let first = Task { try await session.perform { try await $0.favorites() } }
            let second = Task { try await session.perform { try await $0.favorites() } }
            addTeardownBlock {
                SessionRecoveryProtocol.gate.release(host, "login", reply: .failure(.cancelled))
                first.cancel(); second.cancel()
                _ = await first.result; _ = await second.result
                await MainActor.run { session.authorizationChanged = nil }
            }
            try await waitForRequests(host, "favorites", count: 2)
            try await waitForRequests(host, "login", count: 1)
            SessionRecoveryProtocol.gate.release(host, "login", reply: .response(200,
                "{\"ok\":true,\"role\":\"" + role + "\",\"guest\":" + String(guest) + "}"))
            _ = try await first.value
            _ = try await second.value
            XCTAssertEqual(SessionRecoveryProtocol.gate.count(host, "login"), 1)
            XCTAssertEqual(SessionRecoveryProtocol.gate.count(host, "favorites"), 4)
            XCTAssertEqual(notifications, 1, "Waiters sharing one renewal must not repeatedly retire the same authorization")
            XCTAssertEqual(observedRole, role)
            XCTAssertEqual(observedGuest, guest)
            XCTAssertEqual(observedRevision, session.authorizationRevision)
            XCTAssertNotEqual(session.authorizationRevision, authorizationRevision)
            XCTAssertEqual(session.revision, sessionRevision, "An authorization boundary must not cancel independent successful session retries")
            XCTAssertFalse(session.needsSignIn)
            session.authorizationChanged = nil
        }
    }

    func testSameRoleRenewalPreservesCatalogAndListingCaches() async throws {
        let fixture = try AuthorizationRenewalFixture(role: "admin")
        defer { fixture.cleanup() }
        try await fixture.prepare()
        let model = fixture.model
        let catalogRevision = model.catalog.revision
        let sessionRevision = model.sessionStore.revision
        let authorizationRevision = model.sessionStore.authorizationRevision
        let tracks = TrackListing()
        let search = SearchListing()
        let trackRequest = TrackListingRequest(revision: catalogRevision, query: "", filters: .init(), sort: .title)
        let searchRequest = SearchListingRequest(revision: catalogRevision, query: "Private")
        await tracks.update(index: model.catalog.index, request: trackRequest)
        await search.update(index: model.catalog.index, request: searchRequest)
        let trackBuild = tracks.result.buildID
        let searchBuild = search.result.buildID
        let libraryRequests = SessionRecoveryProtocol.gate.count(fixture.host, "library")
        let artistRequests = SessionRecoveryProtocol.gate.count(fixture.host, "artists")
        var notifications = 0
        let onChange = model.sessionStore.authorizationChanged
        model.sessionStore.authorizationChanged = { notifications += 1; onChange?() }
        fixture.renewAs("admin", holdRefresh: false)
        _ = try await model.sessionStore.perform { try await $0.favorites() }
        XCTAssertEqual(notifications, 0)
        XCTAssertEqual(model.sessionStore.revision, sessionRevision)
        XCTAssertEqual(model.sessionStore.authorizationRevision, authorizationRevision)
        XCTAssertEqual(model.catalog.revision, catalogRevision)
        XCTAssertEqual(SessionRecoveryProtocol.gate.count(fixture.host, "library"), libraryRequests)
        XCTAssertEqual(SessionRecoveryProtocol.gate.count(fixture.host, "artists"), artistRequests)
        XCTAssertNotNil(model.catalog.cachedAlbum(fixture.hidden.id))
        await tracks.update(index: model.catalog.index, request: trackRequest)
        await search.update(index: model.catalog.index, request: searchRequest)
        XCTAssertEqual(tracks.result.buildID, trackBuild)
        XCTAssertEqual(search.result.buildID, searchBuild)
        XCTAssertEqual(tracks.result.tracks.map(\.id), [fixture.privateTrack.id])
        XCTAssertTrue(model.personalFavorites.contains(.track, id: fixture.privateTrack.id))
    }

    func testAuthorizationChangeCancellationPreventsRetiredOperationRetry() async throws {
        let (session, _, host) = try fixture(login: [.response(200, success)], requests: [
            .response(401, "{}"), .response(200, #"{"albums":[],"tracks":[]}"#),
        ])
        var request: Task<Favorites, Error>?
        session.authorizationChanged = { request?.cancel() }
        let task = Task {
            try await session.perform { api in
                SessionRecoveryProtocol.gate.recordInvocation(host)
                return try await api.favorites()
            }
        }
        request = task
        defer { session.authorizationChanged = nil; task.cancel() }
        do {
            _ = try await task.value
            XCTFail("A role-scoped task retired by the callback must not resume its old operation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(SessionRecoveryProtocol.gate.count(host, "operation"), 1)
        XCTAssertEqual(SessionRecoveryProtocol.gate.count(host, "favorites"), 1)
        XCTAssertEqual(SessionRecoveryProtocol.gate.count(host, "login"), 1)
        XCTAssertEqual(session.info?.role, "admin")
        XCTAssertFalse(session.needsSignIn)
    }

    func testSuccessfulRenewalDowngradeRetiresPrivilegedCatalogBeforeRefresh() async throws {
        for role in ["admin", "companion"] {
            let fixture = try AuthorizationRenewalFixture(role: role)
            defer { fixture.cleanup() }
            try await fixture.prepare()
            let model = fixture.model
            let catalogRevision = model.catalog.revision
            let sessionRevision = model.sessionStore.revision
            let authorizationRevision = model.sessionStore.authorizationRevision
            let personalRevision = model.personalFavorites.revision
            let personalFile = try PersonalFavoritesStore.fileURL(root: fixture.personalRoot, baseURL: fixture.api.baseURL)
            let savedPersonalBytes = try Data(contentsOf: personalFile)
            let tracks = TrackListing()
            let search = SearchListing()
            await tracks.update(index: model.catalog.index, request: TrackListingRequest(
                revision: catalogRevision, query: "", filters: .init(), sort: .title))
            await search.update(index: model.catalog.index, request: SearchListingRequest(revision: catalogRevision, query: "Private"))
            XCTAssertEqual(tracks.result.tracks.map(\.id), [fixture.privateTrack.id])
            XCTAssertEqual(search.result.tracks.map(\.id), [fixture.privateTrack.id])
            let tone = try XCTUnwrap(Bundle(for: OfflineLaunchTests.self).url(forResource: "tone", withExtension: "flac"))
            model.player.connect(fixture.api, demoURL: tone)
            model.player.play([fixture.privateTrack])
            model.player.pause()
            XCTAssertEqual(model.player.current?.id, fixture.privateTrack.id)
            model.pendingRoute = .album(fixture.hidden.id)
            model.favorites.replace(Favorites(albums: [FavoriteItem(id: fixture.hidden.id)], tracks: []))
            let libraries = SessionRecoveryProtocol.gate.count(fixture.host, "library")
            let artists = SessionRecoveryProtocol.gate.count(fixture.host, "artists")
            let trackRequests = SessionRecoveryProtocol.gate.count(fixture.host, "tracks")
            fixture.renewAs("user", holdRefresh: true)
            let lateArtistTracks = Task { try await model.catalog.artistTracks("Private artist") }
            addTeardownBlock {
                SessionRecoveryProtocol.gate.release(fixture.host, "tracks", reply: .failure(.cancelled))
                lateArtistTracks.cancel()
                _ = await lateArtistTracks.result
            }
            try await waitForRequests(fixture.host, "tracks", count: trackRequests + 1)
            var resetInsideCallback = false
            let onChange = model.sessionStore.authorizationChanged
            model.sessionStore.authorizationChanged = {
                onChange?()
                resetInsideCallback = model.catalog.index.albums.isEmpty && model.catalog.index.tracks.isEmpty
                    && model.catalog.cachedAlbum(fixture.hidden.id) == nil && model.player.current == nil
                    && model.pendingRoute == nil && RememberedSession.load(fixture.defaults)?.role == "user"
            }
            _ = try await model.sessionStore.perform { try await $0.favorites() }
            try await waitForRequests(fixture.host, "library", count: libraries + 1)
            try await waitForRequests(fixture.host, "artists", count: artists + 1)
            XCTAssertTrue(model.signedIn)
            XCTAssertTrue(resetInsideCallback, "Retirement must finish synchronously before the renewed request resumes")
            XCTAssertFalse(model.sessionStore.canSeeHidden)
            XCTAssertEqual(model.sessionStore.revision, sessionRevision)
            XCTAssertNotEqual(model.sessionStore.authorizationRevision, authorizationRevision,
                              "The shell identity must retire all pre-renewal screen state, including cached Track and Search results")
            XCTAssertNotEqual(model.catalog.revision, catalogRevision)
            XCTAssertTrue(model.catalog.index.albums.isEmpty)
            XCTAssertTrue(model.catalog.index.tracks.isEmpty)
            XCTAssertTrue(model.catalog.index.artists.isEmpty)
            XCTAssertFalse(model.catalog.showHidden)
            XCTAssertNil(model.catalog.cachedAlbum(fixture.hidden.id))
            XCTAssertTrue(model.favorites.value.albums.isEmpty && model.favorites.value.tracks.isEmpty)
            XCTAssertNil(model.player.current)
            XCTAssertTrue(model.player.queue.tracks.isEmpty)
            XCTAssertNil(model.pendingRoute)
            XCTAssertEqual(RememberedSession.load(fixture.defaults)?.role, "user")
            XCTAssertEqual(RememberedSession.load(fixture.defaults)?.guest, false)
            XCTAssertEqual(model.personalFavorites.revision, personalRevision)
            XCTAssertTrue(model.personalFavorites.contains(.track, id: fixture.privateTrack.id))
            XCTAssertEqual(try Data(contentsOf: personalFile), savedPersonalBytes)
            XCTAssertFalse(search.matches(SearchListingRequest(revision: model.catalog.revision, query: "Private")))
            let replacementTracks = TrackListing()
            let replacementSearch = SearchListing()
            await replacementTracks.update(index: model.catalog.index, request: TrackListingRequest(
                revision: model.catalog.revision, query: "", filters: .init(), sort: .title))
            await replacementSearch.update(index: model.catalog.index, request: SearchListingRequest(
                revision: model.catalog.revision, query: "Private"))
            XCTAssertTrue(replacementTracks.result.tracks.isEmpty)
            XCTAssertTrue(replacementSearch.result.isEmpty)
            let staleBody = String(decoding: try JSONEncoder().encode([fixture.privateTrack]), as: UTF8.self)
            SessionRecoveryProtocol.gate.release(fixture.host, "tracks", reply: .response(200, staleBody))
            do {
                _ = try await lateArtistTracks.value
                XCTFail("A pre-renewal featured-track response cannot revive the retired catalog")
            } catch { XCTAssertTrue(error is CancellationError) }
            fixture.releaseRefresh()
            for _ in 0..<200 where model.catalog.loading { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertFalse(model.catalog.loading)
            XCTAssertTrue(model.catalog.index.albums.isEmpty && model.catalog.index.tracks.isEmpty)
            XCTAssertNil(model.catalog.cachedAlbum(fixture.hidden.id))
        }
    }
}
