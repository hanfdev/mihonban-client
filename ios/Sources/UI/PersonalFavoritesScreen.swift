import SwiftUI

// Only currently authorized catalog items may resolve a personal bookmark.
// Saved song metadata supports offline launch before a full track list exists.
struct PersonalFavoritesProjection: Sendable {
    var albums: [Album] = []
    var tracks: [Track] = []

    static func build(albums savedAlbums: [Album], tracks savedTracks: [Track],
                      index: CatalogIndex, tracksLoaded: Bool, includeHidden: Bool) -> Self {
        let albums = Dictionary(index.albums.filter { includeHidden || $0.hidden != true }.map { ($0.id, $0) },
                                uniquingKeysWith: { first, _ in first })
        let tracks = Dictionary(index.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Self(albums: savedAlbums.compactMap { albums[$0.id] }, tracks: savedTracks.compactMap { saved in
            if let current = tracks[saved.id] {
                // A parent album can be hidden even when its normalized track is not.
                guard includeHidden || current.hidden != true,
                      let parent = current.albumId, albums[parent] != nil else { return nil }
                return current
            }
            guard !tracksLoaded, let parent = saved.albumId, albums[parent] != nil,
                  includeHidden || saved.hidden != true else { return nil }
            return saved
        })
    }
}

private struct PersonalFavoritesRequest: Equatable {
    let favorites: UUID
    let catalog: UUID
    let tracksLoaded: Bool
    let includeHidden: Bool
}

struct PersonalFavoritesScreen: View {
    let model: AppModel
    @State private var kind: FavoriteKind = .album
    @State private var editing = false
    @State private var preparing = false
    @State private var projection = PersonalFavoritesProjection()
    @State private var completed: PersonalFavoritesRequest?

    private var store: PersonalFavoritesStore { model.personalFavorites }
    private var request: PersonalFavoritesRequest {
        PersonalFavoritesRequest(favorites: store.revision, catalog: model.catalog.revision,
                                 tracksLoaded: model.catalog.tracksLoaded,
                                 includeHidden: model.catalog.showHidden && model.sessionStore.canSeeHidden)
    }
    private var current: PersonalFavoritesProjection {
        completed == request ? projection : PersonalFavoritesProjection()
    }

    var body: some View {
        List {
            Section {
                NavigationLink(value: CatalogRoute.curatedPicks) {
                    Label(L10n.text("personal.curatedTitle"), systemImage: "sparkles")
                }.accessibilityIdentifier("personal.curated.open")
            } footer: {
                Text(L10n.text("personal.hint")).font(Theme.body(12))
            }.listRowBackground(Theme.background)
            Section {
                Picker(L10n.text("personal.title"), selection: $kind) {
                    Text(L10n.text("favs.albums")).tag(FavoriteKind.album)
                    Text(L10n.text("favs.tracks")).tag(FavoriteKind.track)
                }.pickerStyle(.segmented).accessibilityIdentifier("personal.kind")
                    .listRowBackground(Color.clear)
                if !store.isReady && !store.loading {
                    CatalogProblem(message: L10n.text("personal.loadFailed")) {
                        guard model.signedIn, let api = model.client else { return }
                        let session = model.sessionStore.revision
                        Task {
                            guard model.signedIn, session == model.sessionStore.revision else { return }
                            await store.connect(baseURL: api.baseURL)
                        }
                    }
                } else if store.loading || completed != request {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                } else if kind == .album { albumRows } else { trackRows }
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle(L10n.text("personal.title"))
            .environment(\.editMode, .constant(editing ? .active : .inactive))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !(kind == .album ? current.albums.isEmpty : current.tracks.isEmpty) {
                        Button(L10n.text(editing ? "common.done" : "common.edit")) { editing.toggle() }
                            .accessibilityIdentifier("personal.edit").disabled(store.busy)
                    }
                }
            }
            .refreshable { await model.catalog.refresh() }
            .task(id: request) {
                let token = request
                let albums = store.albums
                let tracks = store.tracks
                let index = model.catalog.index
                let loaded = model.catalog.tracksLoaded
                let hidden = model.catalog.showHidden && model.sessionStore.canSeeHidden
                let task = Task.detached(priority: .userInitiated) {
                    PersonalFavoritesProjection.build(albums: albums, tracks: tracks, index: index,
                                                      tracksLoaded: loaded, includeHidden: hidden)
                }
                let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
                guard !Task.isCancelled, token == request else { return }
                projection = result
                completed = token
            }
            .onChange(of: kind) { _, _ in editing = false }
    }

    @ViewBuilder private var albumRows: some View {
        let albums = current.albums
        if albums.isEmpty { empty(hasUnavailable: !store.albums.isEmpty) }
        else {
            if !editing {
                PlayAllRow(player: model.player, identifier: "personal", preparing: preparing) {
                    guard !preparing else { return }
                    preparing = true
                    let session = model.sessionStore.revision
                    Task {
                        defer { preparing = false }
                        guard model.signedIn, session == model.sessionStore.revision else { return }
                        await model.playAlbums(albums)
                    }
                }.moveDisabled(true).deleteDisabled(true)
            }
            ForEach(albums) { album in
                NavigationLink(value: CatalogRoute.album(album.id)) { AlbumRow(album: album, model: model) }
                    .contextMenu { AlbumActions(album: album, model: model) }
                    .accessibilityIdentifier("personal.favorite.album.\(album.id)")
                    .listRowBackground(Theme.background)
            }.onDelete { remove(.album, ids: albums.map(\.id), offsets: $0) }
                .onMove { move(.album, ids: albums.map(\.id), source: $0, destination: $1) }
                .deleteDisabled(store.busy).moveDisabled(store.busy)
        }
    }

    @ViewBuilder private var trackRows: some View {
        let tracks = current.tracks
        if tracks.isEmpty { empty(hasUnavailable: !store.tracks.isEmpty) }
        else {
            if !editing {
                PlayAllRow(player: model.player, identifier: "personal") { model.player.play(tracks) }
                    .moveDisabled(true).deleteDisabled(true)
            }
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                CatalogTrackRow(track: track, model: model, identifier: "personal.favorite.track.\(track.id)") {
                    model.player.play(tracks, index: index)
                }.listRowBackground(Theme.background)
            }.onDelete { remove(.track, ids: tracks.map(\.id), offsets: $0) }
                .onMove { move(.track, ids: tracks.map(\.id), source: $0, destination: $1) }
                .deleteDisabled(store.busy).moveDisabled(store.busy)
        }
    }

    private func empty(hasUnavailable: Bool) -> some View {
        ContentUnavailableView(L10n.text("personal.empty"), systemImage: "heart",
            description: Text(L10n.text(hasUnavailable ? "personal.unavailable" : "personal.emptyHint")))
            .listRowBackground(Color.clear)
    }

    private func remove(_ kind: FavoriteKind, ids: [String], offsets: IndexSet) {
        let targets = offsets.compactMap { ids.indices.contains($0) ? ids[$0] : nil }
        let token = store.revision
        Task {
            guard token == store.revision else { return }
            await store.remove(kind, ids: targets)
        }
    }

    private func move(_ kind: FavoriteKind, ids: [String], source: IndexSet, destination: Int) {
        var reordered = ids
        reordered.move(fromOffsets: source, toOffset: destination)
        let visible = Set(ids)
        let all = kind == .album ? store.albums.map(\.id) : store.tracks.map(\.id)
        let complete = reordered + all.filter { !visible.contains($0) }
        let token = store.revision
        Task {
            guard token == store.revision else { return }
            await store.reorder(kind, ids: complete)
        }
    }
}
