import Foundation
import Observation

nonisolated struct PersonalFavoritesSnapshot: Codable, Sendable {
    var version = 1
    var albums: [Album] = []
    var tracks: [Track] = []
}

// Capture operation order on the main actor, then perform all file work on a
// worker. Stores reopening the same service share the pending operation chain.
@MainActor
final class PersonalFavoritesStorage {
    static let shared = PersonalFavoritesStorage()
    private var pending: [URL: (id: UUID, task: Task<Void, Never>)] = [:]
    private let readFile: @Sendable (URL) throws -> PersonalFavoritesSnapshot
    private let writeFile: @Sendable (PersonalFavoritesSnapshot, URL) throws -> Void

    init(read: @escaping @Sendable (URL) throws -> PersonalFavoritesSnapshot = PersonalFavoritesStorage.read,
         write: @escaping @Sendable (PersonalFavoritesSnapshot, URL) throws -> Void = PersonalFavoritesStorage.write) {
        readFile = read
        writeFile = write
    }

    func load(_ file: URL) async throws -> PersonalFavoritesSnapshot {
        let read = readFile
        return try await enqueue(file) { try read(file) }.value
    }

    func save(_ snapshot: PersonalFavoritesSnapshot, to file: URL) async throws {
        let write = writeFile
        try await enqueue(file) { try write(snapshot, file) }.value
    }

    private func enqueue<Value: Sendable>(_ file: URL,
                                          operation: @escaping @Sendable () throws -> Value) -> Task<Value, Error> {
        let previous = pending[file]?.task
        let id = UUID()
        let result = Task.detached(priority: .userInitiated) {
            await previous?.value
            return try operation()
        }
        let finished = Task.detached { _ = await result.result }
        pending[file] = (id, finished)
        Task {
            await finished.value
            if pending[file]?.id == id { pending.removeValue(forKey: file) }
        }
        return result
    }

    nonisolated static func read(_ file: URL) throws -> PersonalFavoritesSnapshot {
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return PersonalFavoritesSnapshot() }
        let value = try JSONDecoder().decode(PersonalFavoritesSnapshot.self, from: data)
        guard value.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return value
    }

    nonisolated static func write(_ snapshot: PersonalFavoritesSnapshot, _ file: URL) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: MediaPaths.protection)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

// Personal favorites belong to this installation and service, independently of
// administrator picks. The UI resolves these snapshots against its authorized
// catalog before displaying them; stored IDs survive temporarily missing items.
@MainActor @Observable
final class PersonalFavoritesStore {
    private(set) var albums: [Album] = []
    private(set) var tracks: [Track] = []
    private(set) var revision = UUID()
    private(set) var loading = false
    private(set) var busy = false
    private(set) var isReady = false
    var error: String?
    @ObservationIgnored private let root: URL
    @ObservationIgnored private let storage: PersonalFavoritesStorage
    @ObservationIgnored private var file: URL?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var albumIDs: Set<String> = []
    @ObservationIgnored private var trackIDs: Set<String> = []

    init(root: URL = MediaPaths.supportRoot, storage: PersonalFavoritesStorage = .shared) {
        self.root = root
        self.storage = storage
    }

    func connect(baseURL: URL) async {
        reset()
        loading = true
        let token = generation
        defer { if generation == token { loading = false } }
        do {
            let target = try Self.fileURL(root: root, baseURL: baseURL)
            let saved = try await storage.load(target)
            guard generation == token, !Task.isCancelled else { return }
            file = target
            apply(saved)
            isReady = true
        } catch {
            if generation == token, !Task.isCancelled { self.error = L10n.text("personal.loadFailed") }
        }
    }

    func reset() {
        generation = UUID()
        file = nil
        albums = []; tracks = []
        albumIDs.removeAll(); trackIDs.removeAll()
        loading = false; busy = false; isReady = false; error = nil
        revision = UUID()
    }

    func contains(_ kind: FavoriteKind, id: String) -> Bool {
        // Observe the content revision while keeping membership lookup constant-time.
        _ = revision
        return kind == .album ? albumIDs.contains(id) : trackIDs.contains(id)
    }

    func toggle(album: Album) async {
        guard ready, !album.id.isEmpty else { return }
        var next = snapshot
        if albumIDs.contains(album.id) { next.albums.removeAll { $0.id == album.id } }
        else { next.albums.insert(Self.compact(album), at: 0) }
        await commit(next)
    }

    func toggle(track: Track) async {
        guard ready, !track.id.isEmpty else { return }
        var next = snapshot
        if trackIDs.contains(track.id) { next.tracks.removeAll { $0.id == track.id } }
        else { next.tracks.insert(track, at: 0) }
        await commit(next)
    }

    func remove(_ kind: FavoriteKind, ids: [String]) async {
        guard ready else { return }
        let targets = Set(ids)
        let existing = kind == .album ? albumIDs : trackIDs
        guard !targets.isDisjoint(with: existing) else { return }
        var next = snapshot
        if kind == .album { next.albums.removeAll { targets.contains($0.id) } }
        else { next.tracks.removeAll { targets.contains($0.id) } }
        await commit(next)
    }

    func reorder(_ kind: FavoriteKind, ids: [String]) async {
        guard ready else { return }
        let existing = kind == .album ? albumIDs : trackIDs
        guard ids.count == existing.count, Set(ids) == existing else { return }
        var next = snapshot
        if kind == .album {
            guard ids != albums.map(\.id) else { return }
            let byID = Dictionary(uniqueKeysWithValues: albums.map { ($0.id, $0) })
            next.albums = ids.compactMap { byID[$0] }
        } else {
            guard ids != tracks.map(\.id) else { return }
            let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
            next.tracks = ids.compactMap { byID[$0] }
        }
        await commit(next)
    }

    private var ready: Bool { isReady && file != nil && !loading && !busy }
    private var snapshot: PersonalFavoritesSnapshot { PersonalFavoritesSnapshot(albums: albums, tracks: tracks) }

    private func commit(_ next: PersonalFavoritesSnapshot) async {
        guard ready, let target = file else { return }
        busy = true
        error = nil
        let token = generation
        defer { if generation == token { busy = false } }
        do {
            try await storage.save(next, to: target)
            guard generation == token, file == target else { return }
            // Publish only after the atomic write succeeds, so a failed save
            // never leaves a heart selected for an item that was not persisted.
            apply(next)
        } catch {
            if generation == token, file == target { self.error = L10n.text("personal.saveFailed") }
        }
    }

    private func apply(_ value: PersonalFavoritesSnapshot) {
        var albumIDs: Set<String> = []
        var trackIDs: Set<String> = []
        albums = value.albums.filter { !$0.id.isEmpty && albumIDs.insert($0.id).inserted }.map(Self.compact)
        tracks = value.tracks.filter { !$0.id.isEmpty && trackIDs.insert($0.id).inserted }
        self.albumIDs = albumIDs
        self.trackIDs = trackIDs
        revision = UUID()
    }

    private static func compact(_ album: Album) -> Album {
        var result = album
        result.tracks = nil
        result.note = nil
        result.images = nil
        result.similar = nil
        result.folder = nil
        result.storageId = nil
        return result
    }

    nonisolated static func fileURL(root: URL, baseURL: URL) throws -> URL {
        guard var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        parts.scheme = scheme
        parts.host = host.lowercased()
        parts.query = nil
        parts.fragment = nil
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        guard let service = parts.url else { throw CocoaError(.fileReadInvalidFileName) }
        return root.appendingPathComponent(MediaPaths.service(service), isDirectory: true)
            .appendingPathComponent("personal-favorites-v1.json")
    }
}
