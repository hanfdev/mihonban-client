import XCTest
import UIKit
@testable import Mihonban

private actor ArtworkRenewalDirectoryGate {
    private var holdNext = false
    private var waiting: CheckedContinuation<Void, Never>?
    private(set) var completed = 0
    var isWaiting: Bool { waiting != nil }

    func arm() { holdNext = true }

    func prepare(_ directory: URL) async {
        if holdNext {
            holdNext = false
            await withCheckedContinuation { waiting = $0 }
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: MediaPaths.protection)
        completed += 1
    }

    func release() {
        holdNext = false
        waiting?.resume()
        waiting = nil
    }
}

private final class ArtworkRenewalProtocol: URLProtocol {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var roles: [String: String] = [:]
        private var rejectFavorites: Set<String> = []
        private var covers: [String: [ArtworkRenewalProtocol]] = [:]
        private var stopped: Set<ObjectIdentifier> = []
        private var counts: [String: [String: Int]] = [:]

        func authorize(_ host: String, role: String, renewing: Bool = false) {
            lock.withLock {
                roles[host] = role
                if renewing { rejectFavorites.insert(host) }
            }
        }

        func response(_ connection: ArtworkRenewalProtocol) -> (Int, Data)? {
            let url = connection.request.url!
            let host = url.host!
            return lock.withLock {
                counts[host, default: [:]][url.lastPathComponent, default: 0] += 1
                switch url.path {
                case "/cover.png":
                    covers[host, default: []].append(connection)
                    return nil
                case "/api/login", "/api/me":
                    let role = roles[host] ?? "admin"
                    return (200, Data("{\"ok\":true,\"role\":\"\(role)\",\"guest\":false}".utf8))
                case "/api/favorites":
                    if rejectFavorites.remove(host) != nil { return (401, Data("{}".utf8)) }
                    return (200, Data(#"{"albums":[],"tracks":[]}"#.utf8))
                case "/api/library", "/api/artists", "/api/tracks":
                    return (200, Data("[]".utf8))
                default:
                    return (404, Data("{}".utf8))
                }
            }
        }

        func count(_ host: String, _ path: String) -> Int {
            lock.withLock { counts[host]?[path] ?? 0 }
        }

        func stop(_ connection: ArtworkRenewalProtocol) {
            lock.withLock {
                // Only retained cover requests participate in this gate. API
                // request addresses can be reused after their objects deallocate.
                guard let host = connection.request.url?.host,
                      covers[host]?.contains(where: { $0 === connection }) == true else { return }
                _ = stopped.insert(ObjectIdentifier(connection))
            }
        }

        @discardableResult
        func finish(_ host: String, cover: Int, status: Int, data: Data) -> Bool {
            let connection = lock.withLock { () -> ArtworkRenewalProtocol? in
                guard let values = covers[host], values.indices.contains(cover) else { return nil }
                let connection = values[cover]
                guard stopped.insert(ObjectIdentifier(connection)).inserted else { return nil }
                return connection
            }
            guard let connection else { return false }
            connection.respond(status, data: data, mime: "image/png")
            return true
        }

        func remove(_ host: String) {
            lock.withLock {
                for connection in covers.removeValue(forKey: host) ?? [] {
                    stopped.remove(ObjectIdentifier(connection))
                }
                roles[host] = nil
                counts[host] = nil
                rejectFavorites.remove(host)
            }
        }
    }

    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() { Self.state.stop(self) }
    override func startLoading() {
        if let (status, data) = Self.state.response(self) { respond(status, data: data, mime: "application/json") }
    }

    private func respond(_ status: Int, data: Data, mime: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
private final class ArtworkRenewalFixture {
    let host = "artwork-renewal-\(UUID().uuidString.lowercased()).invalid"
    let suiteName = "org.mihonban.artwork-renewal.\(UUID().uuidString)"
    let personalRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let artwork = ArtworkStore()
    let directory = ArtworkRenewalDirectoryGate()
    let transport: URLSession
    let api: APIClient
    let model: AppModel
    let red: Data
    let green: Data
    private var images: [Task<UIImage?, Never>] = []
    private var retainedMedia: MediaCache?
    private(set) var finishedImages = 0

    init() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArtworkRenewalProtocol.self]
        configuration.httpCookieStorage = nil
        transport = URLSession(configuration: configuration)
        api = try APIClient(address: "https://\(host)", session: transport)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = directory
        model = AppModel(defaults: defaults, transport: transport, artworkStore: artwork,
                         personalFavoritesRoot: personalRoot,
                         prepareArtworkDirectory: { await directory.prepare($0) })
        let settings = CacheSettings(defaults: defaults)
        settings.enabled = true
        model.cache = settings
        model.player.cache = settings
        model.player.setForeground(false)
        ArtworkRenewalProtocol.state.authorize(host, role: "admin")
        red = Self.png(.red)
        green = Self.png(.green)
    }

    private static func png(_ color: UIColor) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    func connect() async throws {
        // Finish the fresh-launch flag before explicitly connecting so startup
        // assertions below measure only the role-renewal artwork boundary.
        await model.bootstrap()
        ArtworkRenewalProtocol.state.authorize(host, role: "admin")
        model.address = api.baseURL.absoluteString
        model.password = "artwork-renewal-password"
        await model.connect()
        retainedMedia = model.media
        XCTAssertTrue(model.signedIn)
        XCTAssertEqual(model.session?.role, "admin")
        XCTAssertNil(model.error)
        XCTAssertFalse(RootView(model: model).showsStartupBrand)
        XCTAssertEqual(CredentialStore.read(for: api.baseURL.absoluteString), "artwork-renewal-password")
    }

    func image() -> Task<UIImage?, Never> {
        let request = Task {
            let result = await artwork.image(url: api.url("cover.png"), session: transport, pixels: 32)
            finishedImages += 1
            return result
        }
        images.append(request)
        return request
    }

    func renew(role: String) async throws {
        ArtworkRenewalProtocol.state.authorize(host, role: role, renewing: true)
        _ = try await model.sessionStore.perform { try await $0.favorites() }
        XCTAssertEqual(model.session?.role, role)
    }

    @discardableResult
    func finish(_ cover: Int, status: Int = 200, data: Data? = nil) -> Bool {
        ArtworkRenewalProtocol.state.finish(host, cover: cover, status: status, data: data ?? green)
    }

    func count(_ path: String) -> Int { ArtworkRenewalProtocol.state.count(host, path) }

    func cleanup() async {
        model.sessionStore.authorizationChanged = nil
        model.disconnect()
        await directory.release()
        await model.applyCacheSettings()
        // This fixture owns its artwork actor and transport. Retire its image
        // tasks before removing fixture files; no shared artwork store is used.
        await artwork.configure(disk: nil)
        transport.invalidateAndCancel()
        for task in images { _ = await task.value }
        if let retainedMedia { _ = await retainedMedia.clear() }
        let downloads = MediaPaths.downloads(service: MediaPaths.service(api.baseURL))
        _ = await DownloadManifestStorage.shared.load(directory: downloads)
        ArtworkRenewalProtocol.state.remove(host)
        _ = CredentialStore.save(nil, for: api.baseURL.absoluteString)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: personalRoot)
        try? FileManager.default.removeItem(at: api.cacheDirectory)
        try? FileManager.default.removeItem(at: downloads.deletingLastPathComponent())
    }
}

// Both native device suites select OfflineLaunchTests, including AppModel wiring.
extension OfflineLaunchTests {
    func testRoleChangingRenewalRetiresArtworkSuccessAndFailureBeforeReveal() async throws {
        for oldStatus in [200, 401] {
            let fixture = try ArtworkRenewalFixture()
            addTeardownBlock { await fixture.cleanup() }
            try await fixture.connect()
            let old = fixture.image()
            try await waitForArtworkRenewal { fixture.count("cover.png") == 1 }
            let oldAuthorization = fixture.model.sessionStore.authorizationRevision
            let installed = fixture.model.sessionStore.authorizationChanged
            var callbacks = 0
            fixture.model.sessionStore.authorizationChanged = {
                installed?()
                callbacks += 1
                XCTAssertTrue(fixture.model.restoringArtworkAuthorization)
                XCTAssertTrue(RootView(model: fixture.model).showsStartupBrand,
                              "The replacement shell must wait for the artwork reset")
            }
            try await fixture.renew(role: "user")
            XCTAssertEqual(callbacks, 1)
            XCTAssertNotEqual(fixture.model.sessionStore.authorizationRevision, oldAuthorization)
            try await waitForArtworkRenewal { fixture.finishedImages == 1 }
            let retired = await old.value
            XCTAssertNil(retired, "The old image caller cannot publish into the replacement shell")
            fixture.finish(0, status: oldStatus, data: fixture.red)
            try await waitForArtworkRenewal {
                !fixture.model.restoringArtworkAuthorization && !fixture.model.catalog.loading
                    && fixture.count("library") == 2
            }
            XCTAssertFalse(RootView(model: fixture.model).showsStartupBrand)
            let preparations = await fixture.directory.completed
            XCTAssertEqual(preparations, 1, "A role boundary keeps the existing disk configuration")
            let current = fixture.image()
            try await waitForArtworkRenewal { fixture.count("cover.png") == 2 }
            XCTAssertTrue(fixture.finish(1), "The renewed role's cover must receive the fixture's response")
            try await waitForArtworkRenewal { fixture.finishedImages == 2 }
            let visible = await current.value
            XCTAssertNotNil(visible, "An obsolete success or 401 must not populate the new cache")
            let cached = fixture.image()
            try await waitForArtworkRenewal { fixture.finishedImages == 3 }
            let cachedImage = await cached.value
            XCTAssertEqual(cachedImage?.pngData(), visible?.pngData())
            XCTAssertEqual(fixture.count("cover.png"), 2)
            let media = try XCTUnwrap(fixture.model.media)
            let file = media.artworkDirectory.appendingPathComponent(digest(fixture.api.url("cover.png").absoluteString) + ".img")
            XCTAssertEqual(try Data(contentsOf: file), fixture.green)
        }
    }

    func testSameRoleRenewalKeepsTheInflightArtworkRequestCoalesced() async throws {
        let fixture = try ArtworkRenewalFixture()
        addTeardownBlock { await fixture.cleanup() }
        try await fixture.connect()
        let first = fixture.image()
        try await waitForArtworkRenewal { fixture.count("cover.png") == 1 }
        let authorization = fixture.model.sessionStore.authorizationRevision
        let installed = fixture.model.sessionStore.authorizationChanged
        var callbacks = 0
        fixture.model.sessionStore.authorizationChanged = { installed?(); callbacks += 1 }
        try await fixture.renew(role: "admin")
        XCTAssertEqual(callbacks, 0)
        XCTAssertEqual(fixture.model.sessionStore.authorizationRevision, authorization)
        XCTAssertFalse(fixture.model.restoringArtworkAuthorization)
        XCTAssertFalse(RootView(model: fixture.model).showsStartupBrand)
        let second = fixture.image()
        try await waitForArtworkRenewal { await fixture.artwork.coalescedRequestsForTesting == 1 }
        XCTAssertEqual(fixture.count("cover.png"), 1)
        XCTAssertTrue(fixture.finish(0, data: fixture.red), "The shared current cover must receive the fixture's response")
        try await waitForArtworkRenewal { fixture.finishedImages == 2 }
        let a = await first.value
        let b = await second.value
        XCTAssertNotNil(a)
        XCTAssertEqual(a?.pngData(), b?.pngData())
        let preparations = await fixture.directory.completed
        XCTAssertEqual(preparations, 1, "An unchanged role must preserve the existing artwork configuration")
    }

    func testDisconnectDuringArtworkRenewalCannotRepublishTheRetiredShell() async throws {
        let fixture = try ArtworkRenewalFixture()
        addTeardownBlock { await fixture.cleanup() }
        try await fixture.connect()
        let old = fixture.image()
        try await waitForArtworkRenewal { fixture.count("cover.png") == 1 }
        let installed = fixture.model.sessionStore.authorizationChanged
        var callbacks = 0
        fixture.model.sessionStore.authorizationChanged = {
            installed?()
            callbacks += 1
            XCTAssertTrue(fixture.model.restoringArtworkAuthorization)
            XCTAssertTrue(RootView(model: fixture.model).showsStartupBrand)
            // Sign out synchronously before the queued artwork worker runs.
            fixture.model.disconnect()
        }
        do {
            try await fixture.renew(role: "user")
            XCTFail("Signing out invalidates the request which caused renewal")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(callbacks, 1)
        await fixture.model.applyCacheSettings()
        XCTAssertFalse(fixture.model.restoringArtworkAuthorization)
        try await waitForArtworkRenewal { fixture.finishedImages == 1 }
        let retired = await old.value
        XCTAssertNil(retired)
        fixture.finish(0, data: fixture.red)
        XCTAssertFalse(fixture.model.signedIn)
        XCTAssertNil(fixture.model.client)
        XCTAssertNil(fixture.model.media)
        XCTAssertNil(fixture.model.downloads)
        XCTAssertFalse(fixture.model.restoringArtworkAuthorization)
        XCTAssertFalse(RootView(model: fixture.model).showsStartupBrand)
        XCTAssertTrue(fixture.model.catalog.albums.isEmpty)
        XCTAssertEqual(fixture.count("library"), 1, "The retired boundary must not reconnect after sign-out")

        // A replacement session passes through the same serial retirement
        // chain; a late old worker must not cancel this session's cover.
        fixture.model.sessionStore.authorizationChanged = installed
        try await fixture.connect()
        let replacement = fixture.image()
        try await waitForArtworkRenewal { fixture.count("cover.png") == 2 }
        XCTAssertTrue(fixture.finish(1), "The replacement session's cover must receive the fixture's response")
        try await waitForArtworkRenewal { fixture.finishedImages == 2 }
        let current = await replacement.value
        XCTAssertNotNil(current)
        XCTAssertEqual(fixture.model.session?.role, "admin")
        XCTAssertFalse(fixture.model.restoringArtworkAuthorization)
        XCTAssertEqual(fixture.count("library"), 2)
    }

    func testCachePreparationCannotReopenTheOldArtworkAuthorizationDuringRenewal() async throws {
        let fixture = try ArtworkRenewalFixture()
        addTeardownBlock { await fixture.cleanup() }
        try await fixture.connect()
        let old = fixture.image()
        try await waitForArtworkRenewal { fixture.count("cover.png") == 1 }
        await fixture.directory.arm()
        let cacheChange = Task { await fixture.model.applyCacheSettings() }
        addTeardownBlock {
            await fixture.directory.release()
            await cacheChange.value
        }
        try await waitForArtworkRenewal { await fixture.directory.isWaiting }
        try await fixture.renew(role: "user")
        try await waitForArtworkRenewal { !fixture.model.restoringArtworkAuthorization }
        try await waitForArtworkRenewal { fixture.finishedImages == 1 }
        let retired = await old.value
        XCTAssertNil(retired)
        fixture.finish(0, status: 401)
        let current = fixture.image()
        try await waitForArtworkRenewal { fixture.count("cover.png") == 2 }
        await fixture.directory.release()
        await cacheChange.value
        XCTAssertTrue(fixture.finish(1), "The replacement cover must receive the fixture's response")
        try await waitForArtworkRenewal { fixture.finishedImages == 2 }
        let visible = await current.value
        XCTAssertNotNil(visible, "A cache-only preparation must preserve the replacement role's image caller")
        XCTAssertFalse(fixture.model.restoringArtworkAuthorization)
        XCTAssertEqual(fixture.model.session?.role, "user")
        XCTAssertEqual(fixture.count("cover.png"), 2)
    }

    func testSuppressedArtworkRenewalBoundaryReproducesStaleCoalescingAndMissingCache() async throws {
        for oldStatus in [200, 401] {
            let fixture = try ArtworkRenewalFixture()
            addTeardownBlock { await fixture.cleanup() }
            try await fixture.connect()
            let old = fixture.image()
            try await waitForArtworkRenewal { fixture.count("cover.png") == 1 }
            let authorization = fixture.model.sessionStore.authorizationRevision
            let installed = fixture.model.sessionStore.authorizationChanged
            var callbacks = 0
            // Isolate the missing application callback without bypassing the
            // real 401/login/retry or changing ArtworkStore itself.
            fixture.model.sessionStore.authorizationChanged = { callbacks += 1 }
            defer { fixture.model.sessionStore.authorizationChanged = installed }
            try await fixture.renew(role: "user")
            XCTAssertEqual(callbacks, 1)
            XCTAssertNotEqual(fixture.model.sessionStore.authorizationRevision, authorization)
            let replacement = fixture.image()
            try await waitForArtworkRenewal { await fixture.artwork.coalescedRequestsForTesting == 1 }
            XCTAssertEqual(fixture.count("cover.png"), 1, "Without the boundary, the new role joins the old request")
            XCTAssertTrue(fixture.finish(0, status: oldStatus, data: fixture.red),
                          "The baseline request must receive the controlled success or failure response")
            try await waitForArtworkRenewal { fixture.finishedImages == 2 }
            let a = await old.value
            let b = await replacement.value
            if oldStatus == 200 { XCTAssertNotNil(a) }
            else { XCTAssertNil(a) }
            XCTAssertEqual(a?.pngData(), b?.pngData())
            let cached = fixture.image()
            try await waitForArtworkRenewal { fixture.finishedImages == 3 }
            let cacheResult = await cached.value
            XCTAssertEqual(cacheResult?.pngData(), a?.pngData())
            XCTAssertEqual(fixture.count("cover.png"), 1,
                           "The old success or negative cache still suppresses a fresh image request")
        }
    }

    private func waitForArtworkRenewal(_ condition: @MainActor () async -> Bool,
                                       file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<250 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("The artwork renewal fixture did not reach its deterministic gate", file: file, line: line)
        throw URLError(.timedOut)
    }
}
