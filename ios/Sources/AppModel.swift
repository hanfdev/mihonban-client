import Foundation
import Observation

// The last session the service authorized, kept so a cold launch without a
// connection can reopen that service's saved library and downloads.
struct RememberedSession: Codable, Equatable {
    var address: String
    var role: String?
    var guest: Bool?
    private static let key = "rememberedSession"

    static func load(_ defaults: UserDefaults) -> RememberedSession? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(RememberedSession.self, from: $0) }
    }

    static func save(_ value: RememberedSession?, _ defaults: UserDefaults) {
        if let value, let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
}

// Composes the service session with the catalog, favorites and player stores.
// Domain rules live in those stores; this type only wires connection state.
@MainActor @Observable
final class AppModel {
    private(set) var isBootstrapping = true
    var connecting = false
    var error: String?
    var address: String
    var password = ""
    var rememberPassword = true
    var demo = false
    // A route requested outside a navigation stack, such as from Now Playing.
    var pendingRoute: CatalogRoute?
    var cache = CacheSettings()
    let sessionStore: SessionStore
    let favorites: FavoritesStore
    let personalFavorites: PersonalFavoritesStore
    let catalog: CatalogStore
    let player = PlayerModel()
    // Per-service storage, present only while signed in to a real service.
    private(set) var media: MediaCache?
    private(set) var downloads: DownloadStore?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let defaults: UserDefaults
    // Tests substitute the transport; nil uses the app's shared configuration.
    @ObservationIgnored private let transport: URLSession?
    @ObservationIgnored private let artworkStore: ArtworkStore
    @ObservationIgnored private let prepareArtworkDirectory: @Sendable (URL) async -> Void
    @ObservationIgnored private var artworkConfiguration = UUID()

    init(defaults: UserDefaults = .standard, transport: URLSession? = nil,
         artworkStore: ArtworkStore = .shared,
         personalFavoritesRoot: URL = MediaPaths.supportRoot,
         prepareArtworkDirectory: @escaping @Sendable (URL) async -> Void = { target in
             await Task.detached(priority: .utility) {
                 try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true,
                                                         attributes: MediaPaths.protection)
             }.value
         }) {
        self.defaults = defaults
        personalFavorites = PersonalFavoritesStore(root: personalFavoritesRoot)
        self.transport = transport
        self.artworkStore = artworkStore
        self.prepareArtworkDirectory = prepareArtworkDirectory
        address = defaults.string(forKey: "serviceAddress") ?? ""
        let session = SessionStore()
        let favorites = FavoritesStore(session: session)
        sessionStore = session
        self.favorites = favorites
        catalog = CatalogStore(session: session, favorites: favorites)
        player.cache = cache
        cache.preloadDidChange = { [weak player = player] in player?.preloadSettingsChanged() }
        catalog.localAlbum = { [weak self] id in self?.downloads?.albums[id] }
        session.authorizationRejected = { [weak self] address in
            guard let self else { return }
            if self.client?.baseURL == address { self.personalFavorites.reset() }
            guard RememberedSession.load(self.defaults)?.address == address.absoluteString else { return }
            RememberedSession.save(nil, self.defaults)
        }
    }

    var client: APIClient? { sessionStore.client }
    var session: SessionInfo? { sessionStore.info }
    // Image requests are skipped in demo mode, whose service address is fake.
    var imageClient: APIClient? { demo ? nil : sessionStore.client }
    var signedIn: Bool { sessionStore.info?.ok == true && !sessionStore.needsSignIn }

    // Returns false when some files could not be removed.
    func clearCache() async -> Bool {
        client?.session.configuration.urlCache?.removeAllCachedResponses()
        guard let media else { return true }
        let ok = await media.clear()
        await configureArtwork()
        return ok
    }

    // Applies a changed cache switch or limit at once.
    func cacheSettingsChanged() {
        Task { await applyCacheSettings() }
    }

    func applyCacheSettings() async {
        let media = media
        // Retire old artwork writers before deleting files when caching is off.
        await configureArtwork()
        guard self.media === media else { return }
        media?.prune(protecting: player.protectedFiles)
    }

    private func configureArtwork() async {
        let token = UUID()
        artworkConfiguration = token
        let session = generation
        let media = media
        let enabled = cache.enabled
        let directory = enabled ? media?.artworkDirectory : nil
        if let directory { await prepareArtworkDirectory(directory) }
        // Directory creation may finish after a toggle, clear or disconnect.
        // Its old destination must never become the current artwork cache.
        guard artworkConfiguration == token, generation == session, self.media === media,
              cache.enabled == enabled, directory == (cache.enabled ? self.media?.artworkDirectory : nil) else { return }
        await artworkStore.configure(disk: directory, preservingRequests: true)
    }

    private func attachStorage(_ api: APIClient) async {
        downloads?.detach()
        let media = MediaCache(root: api.cacheDirectory.appendingPathComponent("media", isDirectory: true), settings: cache)
        let downloads = DownloadStore(client: api)
        self.media = media
        self.downloads = downloads
        player.media = media
        player.downloads = downloads
        // Files from the cache layout before generations were introduced.
        let legacy = api.cacheDirectory.appendingPathComponent("audio", isDirectory: true)
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: legacy) }
        await configureArtwork()
        media.prune()
        await downloads.load()
    }

    // List rows hold album summaries, so the full track list is loaded first.
    func downloadAlbum(_ id: String) async {
        do { await downloads?.download(album: try await catalog.album(id)) }
        catch where isRequestCancellation(error) { return }
        catch { player.error = error.localizedDescription }
    }

    // A deleted album's files are gone from the service, so its offline copy goes too.
    func deleteAlbum(_ id: String, files: Bool) async throws {
        try await catalog.delete(id, files: files)
        downloads?.remove(album: id)
    }

    func download(_ track: Track) async {
        guard let albumID = track.albumId, !albumID.isEmpty else { return }
        do { await downloads?.download(album: try await catalog.album(albumID), only: track.id) }
        catch where isRequestCancellation(error) { return }
        catch { player.error = error.localizedDescription }
    }

    func bootstrap() async {
        guard isBootstrapping else { return }
        // Do not show an editable login form while restoring a saved session.
        defer { isBootstrapping = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo"), let api = try? APIClient(address: "https://example.invalid") {
            demo = true
            sessionStore.connect(api, info: SessionInfo(ok: true, role: "user", guest: true))
            let albums = DemoLibrary.albums
            let tracks = ProcessInfo.processInfo.arguments.contains("--demo-large-tracks")
                ? (0..<10_000).reversed().map {
                    Track(id: "large-\($0)", title: "Song \($0)", duration: 300,
                          albumId: "demo-1", albumTitle: "夜の余白", artist: "見本盤スタジオ")
                } : albums.flatMap(\.normalizedTracks)
            catalog.seed(albums: albums, artists: DemoLibrary.artists, tracks: tracks)
            player.connect(api, demoURL: try? DemoLibrary.tone())
            await personalFavorites.connect(baseURL: api.baseURL)
            return
        }
        #endif
        guard !address.isEmpty else { return }
        await connect(automatic: true)
    }

    func connect(automatic: Bool = false) async {
        guard !connecting else { return }
        connecting = true
        error = nil
        let token = generation
        defer { if token == generation { connecting = false } }
        let api: APIClient
        do { api = try APIClient(address: address, session: transport) }
        catch {
            self.error = (error as? ClientError)?.errorDescription ?? L10n.text("mobile.connectionFailed")
            return
        }
        do {
            let saved = CredentialStore.read(for: api.baseURL.absoluteString)
            let supplied = automatic ? (saved ?? "") : password
            let state: SessionInfo
            if !supplied.isEmpty { state = try await api.login(password: supplied) }
            else { state = try await api.me() }
            guard token == generation else { return }
            guard state.ok else { throw ClientError.sessionExpired }
            if !automatic {
                if !CredentialStore.save(rememberPassword ? supplied : nil, for: api.baseURL.absoluteString) {
                    error = L10n.text("mobile.keychainFailed")
                }
            }
            password = ""
            address = api.baseURL.absoluteString
            defaults.set(address, forKey: "serviceAddress")
            RememberedSession.save(RememberedSession(address: address, role: state.role, guest: state.guest), defaults)
            await open(api, info: state, token: token)
        } catch {
            guard token == generation, !isRequestCancellation(error), !Task.isCancelled else { return }
            if isRejected(error) { RememberedSession.save(nil, defaults) }
            else if automatic, isUnreachable(error), let saved = RememberedSession.load(defaults),
                    saved.address == api.baseURL.absoluteString {
                // Only a service that authorized this device before, and is now
                // unreachable rather than refusing, reopens from local data.
                password = ""
                await open(api, info: SessionInfo(ok: true, role: saved.role, guest: saved.guest), token: token)
                return
            }
            self.error = (error as? ClientError)?.errorDescription ?? L10n.text("mobile.connectionFailed")
        }
    }

    private func open(_ api: APIClient, info: SessionInfo, token: UUID) async {
        // Retire the previous authorization before publishing a new shell.
        // Cache-only configuration must not cancel this mandatory boundary.
        await artworkStore.configure(disk: nil)
        guard token == generation else { return }
        // Invalidate the previous catalog before publishing a new authorization.
        // Storage setup can suspend, allowing the new shell to appear meanwhile.
        catalog.reset()
        favorites.reset()
        personalFavorites.reset()
        // Metadata is shown only after authorization, never while signed out.
        sessionStore.connect(api, info: info)
        player.connect(api)
        await personalFavorites.connect(baseURL: api.baseURL)
        guard token == generation else { return }
        await attachStorage(api)
        guard token == generation else { return }
        await catalog.connect()
    }

    func refresh() async {
        guard signedIn, !demo else { return }
        await catalog.refresh()
    }

    func album(_ id: String) async throws -> Album {
        try await catalog.album(id)
    }

    func playAlbums(_ albums: [Album], shuffle: Bool? = nil) async {
        let intent = player.reservePlaybackIntent()
        let session = sessionStore.revision
        do {
            let tracks = try await catalog.playbackTracks(for: albums)
            guard !Task.isCancelled, session == sessionStore.revision, intent == player.playbackIntent else { return }
            if tracks.isEmpty { throw ClientError(key: "mobile.incompleteQueue") }
            player.play(tracks, shuffle: shuffle)
        } catch {
            if !(error is CancellationError), session == sessionStore.revision, intent == player.playbackIntent {
                player.error = error.localizedDescription
            }
        }
    }

    func playAlbum(_ id: String, shuffle: Bool? = nil) async {
        let intent = player.reservePlaybackIntent()
        do {
            let tracks = try await catalog.album(id).normalizedTracks
            guard !tracks.isEmpty, intent == player.playbackIntent, !Task.isCancelled else { return }
            player.play(tracks, shuffle: shuffle)
        } catch {
            if !(error is CancellationError), intent == player.playbackIntent { player.error = error.localizedDescription }
        }
    }

    func enqueueAlbum(_ id: String, next: Bool) async {
        do { player.enqueue(try await catalog.album(id).normalizedTracks, next: next) }
        catch where isRequestCancellation(error) { return }
        catch { player.error = error.localizedDescription }
    }

    // Matches the web artist page: owned albums in catalog order, then guest appearances.
    func playArtist(_ name: String, shuffle: Bool? = nil) async {
        let intent = player.reservePlaybackIntent()
        do {
            var tracks: [Track] = []
            let owned = catalog.index.albums.filter { $0.credits.contains { $0.name == name } }
                .sorted { ($0.year ?? 0, $0.title) < ($1.year ?? 0, $1.title) }
            for album in owned { tracks += try await catalog.album(album.id).normalizedTracks }
            tracks += try await catalog.artistTracks(name)
            guard !tracks.isEmpty, intent == player.playbackIntent, !Task.isCancelled else { return }
            player.play(tracks, shuffle: shuffle)
        } catch {
            if !(error is CancellationError), intent == player.playbackIntent { player.error = error.localizedDescription }
        }
    }

    func disconnect() {
        generation = UUID()
        artworkConfiguration = UUID()
        let token = generation
        player.stop()
        // Downloaded files stay on disk for the next sign-in to this service;
        // they are reachable only through an authorized session's manifest.
        downloads?.detach()
        downloads = nil
        media = nil
        player.media = nil
        player.downloads = nil
        Task {
            guard generation == token, media == nil else { return }
            await artworkStore.configure(disk: nil)
        }
        if let client {
            client.clearCookies()
            _ = CredentialStore.save(nil, for: client.baseURL.absoluteString)
        }
        RememberedSession.save(nil, defaults)
        sessionStore.invalidate()
        catalog.reset()
        favorites.reset()
        personalFavorites.reset()
        pendingRoute = nil
        password = ""
        error = nil
        connecting = false
        demo = false
    }
}
