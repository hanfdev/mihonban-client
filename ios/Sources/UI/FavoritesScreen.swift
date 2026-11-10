import SwiftUI

enum FavoriteSort: String, CaseIterable, Sendable {
    case order, rating, artist, title, yearNew
    var label: String { self == .order ? "favs.sortOrder" : AlbumSort(rawValue: rawValue)?.label ?? "library.sortTitle" }
}

struct FavoritesScreen: View {
    let model: AppModel
    @State private var kind: FavoriteKind = .album
    @State private var sort: FavoriteSort = .order
    @State private var editing = false
    @State private var preparing = false

    private var canEdit: Bool { model.sessionStore.isAdmin && sort == .order }

    private var albums: [Album] {
        let byID = Dictionary(model.catalog.index.albums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let picked = model.favorites.value.albums.compactMap { byID[$0.id] }
        switch sort {
        case .order: return picked
        case .rating: return picked.sorted { CatalogIndex.compare($0, $1, sort: .rating) }
        case .artist: return picked.sorted { CatalogIndex.compare($0, $1, sort: .artist) }
        case .title: return picked.sorted { CatalogIndex.compare($0, $1, sort: .title) }
        case .yearNew: return picked.sorted { CatalogIndex.compare($0, $1, sort: .yearNew) }
        }
    }

    private var tracks: [Track] {
        let byID = Dictionary(model.catalog.index.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let picked = model.favorites.value.tracks.compactMap { byID[$0.id] }
        switch sort {
        case .order, .rating: return picked
        case .artist: return picked.sorted { CatalogIndex.compare($0, $1, sort: .artist) }
        case .title: return picked.sorted { CatalogIndex.compare($0, $1, sort: .title) }
        case .yearNew: return picked.sorted { CatalogIndex.compare($0, $1, sort: .yearNew) }
        }
    }

    var body: some View {
        List {
            Section {
                Picker(L10n.text("nav.favs"), selection: $kind) {
                    Text(L10n.text("favs.albums")).tag(FavoriteKind.album)
                    Text(L10n.text("favs.tracks")).tag(FavoriteKind.track)
                }.pickerStyle(.segmented).listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                if let error = model.player.error ?? model.favorites.error ?? model.catalog.error {
                    CatalogProblem(message: error) { Task { await model.catalog.refresh() } }
                }
            }
            if kind == .album { albumSection } else { trackSection }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(Theme.background)
        .environment(\.editMode, .constant(editing && canEdit ? .active : .inactive))
        .refreshable { await model.catalog.refresh() }
        .overlay { if isEmpty { empty } }
        .navigationTitle(L10n.text("personal.curatedTitle"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(L10n.text("mobile.sort"), selection: $sort) {
                        ForEach(FavoriteSort.allCases, id: \.self) { Text(L10n.text($0.label)).tag($0) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel(L10n.text("mobile.sort"))
            }
            ToolbarItem(placement: .topBarLeading) {
                if canEdit && !isEmpty {
                    Button(L10n.text(editing ? "common.done" : "common.edit")) { withAnimation { editing.toggle() } }
                        .accessibilityIdentifier("favorites.edit")
                }
            }
        }
        .task(id: kind) { await model.catalog.refresh() }
        .task(id: model.favorites.value.tracks.map(\.id)) {
            let known = Set(model.catalog.tracks.map(\.id))
            if model.favorites.value.tracks.contains(where: { !known.contains($0.id) }) {
                await model.catalog.ensureTracks(force: true)
            }
        }
        .onChange(of: canEdit) { _, value in if !value { editing = false } }
    }

    private var isEmpty: Bool {
        kind == .album ? albums.isEmpty && !model.catalog.loading
            : tracks.isEmpty && model.catalog.tracksLoaded
    }

    private var empty: some View {
        ContentUnavailableView(L10n.text(kind == .album ? "favs.emptyAlbums" : "favs.emptyTracks"), systemImage: "sparkles",
            description: Text(L10n.text(model.sessionStore.isAdmin ? "favs.emptyHintAdmin" : "favs.emptyHintUser")))
    }

    @ViewBuilder
    private var albumSection: some View {
        let list = albums
        Section {
            if !list.isEmpty && !editing {
                PlayAllRow(player: model.player, identifier: "favorites", preparing: preparing) {
                    guard !preparing else { return }
                    preparing = true
                    Task {
                        defer { preparing = false }
                        await model.playAlbums(list)
                    }
                }
                    .moveDisabled(true).deleteDisabled(true)
            }
            ForEach(list) { album in
                NavigationLink(value: CatalogRoute.album(album.id)) { AlbumRow(album: album, model: model) }
                    .listRowBackground(Theme.background).accessibilityIdentifier("favorite.\(album.id)")
                    .contextMenu { AlbumActions(album: album, model: model) }
            }
            .onMove(perform: canEdit ? mover(.album, ids: list.map(\.id)) : nil)
            .onDelete(perform: model.sessionStore.isAdmin ? remover(.album, ids: list.map(\.id)) : nil)
        }
    }

    @ViewBuilder
    private var trackSection: some View {
        let list = tracks
        Section {
            if !list.isEmpty && !editing {
                PlayAllRow(player: model.player, identifier: "favorites") { model.player.play(list) }
                    .moveDisabled(true).deleteDisabled(true)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                CatalogTrackRow(track: track, model: model) { model.player.play(list, index: index) }
                    .listRowBackground(Theme.background)
            }
            .onMove(perform: canEdit ? mover(.track, ids: list.map(\.id)) : nil)
            .onDelete(perform: model.sessionStore.isAdmin ? remover(.track, ids: list.map(\.id)) : nil)
        }
        if model.catalog.loadingTracks && list.isEmpty { ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear) }
    }

    private func mover(_ kind: FavoriteKind, ids: [String]) -> (IndexSet, Int) -> Void {
        { source, destination in move(kind, ids: ids, from: source, to: destination) }
    }

    private func remover(_ kind: FavoriteKind, ids: [String]) -> (IndexSet) -> Void {
        { offsets in remove(kind, ids: ids, at: offsets) }
    }

    private func move(_ kind: FavoriteKind, ids: [String], from source: IndexSet, to destination: Int) {
        var reordered = ids
        reordered.move(fromOffsets: source, toOffset: destination)
        // The server requires the complete list, including picks hidden by filters.
        let all = (kind == .album ? model.favorites.value.albums : model.favorites.value.tracks).map(\.id)
        let rest = all.filter { !Set(ids).contains($0) }
        Task { await model.favorites.reorder(kind, ids: reordered + rest) }
    }

    private func remove(_ kind: FavoriteKind, ids: [String], at offsets: IndexSet) {
        let targets = offsets.map { ids[$0] }
        Task { for id in targets { await model.favorites.toggle(kind, id: id) } }
    }

}
