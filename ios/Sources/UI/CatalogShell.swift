import SwiftUI

// Every tab owns its own path; cross-links reuse the currently selected stack.
enum LibraryTab: String, CaseIterable { case albums, artists, tracks, favorites, search }
enum CatalogRoute: Hashable {
    case album(String)
    case artist(String)
    case genre(String)
    case albumSearch(String)
    case trackSearch(String)
    case curatedPicks
}

struct CatalogShell: View {
    @Bindable var model: AppModel
    @State private var selected: LibraryTab = .albums
    @State private var paths: [LibraryTab: [CatalogRoute]] = [:]
    @State private var settings = false

    var body: some View {
        PlayerPresentation(model: model) { library }
            .alert(L10n.text("personal.problemTitle"), isPresented: Binding(
                get: { model.personalFavorites.error != nil },
                set: { if !$0 { model.personalFavorites.error = nil } })) {
                Button(L10n.text("common.done"), role: .cancel) { model.personalFavorites.error = nil }
            } message: { Text(model.personalFavorites.error ?? "") }
    }

    private var library: some View {
        Group {
            if #available(iOS 18.0, *) { modernTabs }
            else { legacyTabs }
        }
        .sheet(isPresented: $settings) { SettingsView(model: model).modifier(AppAppearance()) }
        // Context menus and Now Playing request links here; the selected tab pushes them.
        .onChange(of: model.pendingRoute) { _, route in
            guard let route else { return }
            model.pendingRoute = nil
            model.player.isExpanded = false
            // Opening the page that is already on screen only closes the player.
            if paths[selected]?.last != route { paths[selected, default: []].append(route) }
        }
    }

    @available(iOS 18.0, *)
    private var modernTabs: some View {
        TabView(selection: $selected) {
            Tab(L10n.text("nav.library"), systemImage: "square.grid.2x2", value: .albums) { stack(.albums) }
            Tab(L10n.text("nav.artists"), systemImage: "person.2", value: .artists) { stack(.artists) }
            Tab(L10n.text("nav.tracks"), systemImage: "music.note.list", value: .tracks) { stack(.tracks) }
            Tab(L10n.text("personal.tab"), systemImage: "heart", value: .favorites) { stack(.favorites) }
            Tab(L10n.text("common.search"), systemImage: "magnifyingglass", value: .search, role: .search) { stack(.search) }
        }.tabViewStyle(.sidebarAdaptable)
    }

    private var legacyTabs: some View {
        TabView(selection: $selected) {
            stack(.albums).tabItem { Label(L10n.text("nav.library"), systemImage: "square.grid.2x2") }.tag(LibraryTab.albums)
            stack(.artists).tabItem { Label(L10n.text("nav.artists"), systemImage: "person.2") }.tag(LibraryTab.artists)
            stack(.tracks).tabItem { Label(L10n.text("nav.tracks"), systemImage: "music.note.list") }.tag(LibraryTab.tracks)
            stack(.favorites).tabItem { Label(L10n.text("personal.tab"), systemImage: "heart") }.tag(LibraryTab.favorites)
            stack(.search).tabItem { Label(L10n.text("common.search"), systemImage: "magnifyingglass") }.tag(LibraryTab.search)
        }
    }

    private func stack(_ tab: LibraryTab) -> some View {
        NavigationStack(path: Binding(get: { paths[tab] ?? [] }, set: { paths[tab] = $0 })) {
            Group {
                switch tab {
                case .albums: AlbumsScreen(model: model)
                case .artists: ArtistsScreen(model: model)
                case .tracks: TracksScreen(model: model)
                case .favorites: PersonalFavoritesScreen(model: model)
                case .search: SearchScreen(model: model)
                }
            }
            .modifier(LibraryPlayerInset(model: model))
            .navigationDestination(for: CatalogRoute.self) { route in
                Group {
                    switch route {
                    case .curatedPicks: FavoritesScreen(model: model)
                    case .album(let id): AlbumView(model: model, albumID: id)
                    case .artist(let name): ArtistScreen(model: model, name: name)
                    case .genre(let genre): AlbumsScreen(model: model, initialGenre: genre)
                    case .albumSearch(let query): AlbumsScreen(model: model, initialQuery: query)
                    case .trackSearch(let query): TracksScreen(model: model, initialQuery: query)
                    }
                }.modifier(LibraryPlayerInset(model: model))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel(L10n.text("mobile.settings")).accessibilityIdentifier("settings.open")
                }
            }
        }
        .accessibilityHidden(model.player.isExpanded)
    }
}

// Apply the reservation to each navigation page. An inset on the outer stack
// can leave a pushed ScrollView unaware of the floating player's occupied area.
// SwiftUI measures the actual bar, including Dynamic Type, in every orientation.
private struct LibraryPlayerInset: ViewModifier {
    let model: AppModel

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: model.player.current == nil ? 0 : 16) {
            if #available(iOS 26.0, *), model.player.current != nil {
                NativeMiniPlayer(model: model)
                    .padding(8).frame(maxWidth: 900)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 12).padding(.bottom, 8)
            } else if model.player.current != nil {
                MiniPlayer(model: model)
            }
        }
    }
}

struct NativeMiniPlayer: View {
    let model: AppModel
    var body: some View {
        HStack(spacing: 10) {
            Button { model.player.isExpanded = true } label: {
                HStack(spacing: 10) {
                    Cover(albumID: model.player.current?.albumId ?? "", size: 160, client: model.imageClient)
                        .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
                    MiniPlayerMetadata(title: model.player.current?.title ?? "",
                                       artists: PlaybackCredits(track: model.player.current).compactText)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("player.expand")
                .modifier(PlayerSwipe(expanding: true))
            Button { model.player.toggle() } label: {
                Group {
                    if model.player.isLoading { ProgressView() }
                    else { Image(systemName: model.player.wantsPlayback ? "pause.fill" : "play.fill") }
                }.font(.system(size: 20, weight: .medium))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("mini.toggle")
                .accessibilityLabel(L10n.text(model.player.wantsPlayback ? "common.pause" : "common.play"))
            Button { model.player.next() } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 20, weight: .medium))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("mini.next")
                .accessibilityLabel(L10n.text("player.next"))
        }.padding(.horizontal, 12).padding(.vertical, 4)
            // Safe-area content has its own host and needs its own AX boundary.
            .accessibilityHidden(model.player.isExpanded)
    }
}

struct MiniPlayerMetadata: View {
    let title: String
    let artists: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.body(15, weight: .semibold)).lineLimit(1)
                .accessibilityIdentifier("mini.title")
            Text(artists).font(Theme.body(12)).foregroundStyle(.secondary).lineLimit(1)
                .accessibilityIdentifier("mini.artists")
        }.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
