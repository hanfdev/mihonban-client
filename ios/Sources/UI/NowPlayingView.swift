import AVKit
import SwiftUI

struct MiniPlayer: View {
    let model: AppModel
    var body: some View {
        if let track = model.player.current {
            HStack(spacing: 12) {
                Button { model.player.isExpanded = true } label: {
                    HStack(spacing: 12) {
                        Cover(albumID: track.albumId ?? "", size: 160, client: model.imageClient)
                            .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title).font(Theme.body(14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                            Text(model.player.isLoading ? L10n.text("mobile.preparing") : PlaybackCredits(track: track).compactText)
                                .font(Theme.body(12)).foregroundStyle(Theme.dim).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("player.expand")
                    .modifier(PlayerSwipe(expanding: true))
                PlayButton(player: model.player, diameter: 36)
                IconButton(symbol: "forward.end.fill", label: L10n.text("player.next")) { model.player.next() }
            }.padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.surface)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
                .accessibilityHidden(model.player.isExpanded)
        }
    }
}

struct NowPlayingView: View {
    private enum Space { case viewport, surface }
    let model: AppModel
    @State private var queueVisible = false
    @State private var creditsSheet: CreditsSelection?
    @State private var pendingArtist: (trackID: String, name: String)?
    @State private var scrubbing = false
    @State private var routePickerPresented = false
    @State private var sharing: ShareSelection?
    @State private var scrollTop: CGFloat = 0
    @State private var hitRegions = PlayerHitRegions()
    @Environment(\.playerTransitionActive) private var transitioning
    @Environment(\.playerViewportCenterY) private var viewportCenterY

    private var player: PlayerModel { model.player }
    private var isTablet: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    var body: some View {
        #if DEBUG
        let _ = { PlayerRenderWork.content += 1 }()
        #endif
        GeometryReader { surface in
            VStack(spacing: 0) {
                header
                GeometryReader { geometry in
                    ScrollView {
                        let side = NowPlayingLayout.coverSide(in: geometry.size, controlsHeight: 0, isTablet: isTablet)
                        let width = NowPlayingLayout.controlsWidth(in: geometry.size, coverSide: side, isTablet: isTablet)
                        let style = NowPlayingLayout.controlStyle(in: geometry.size, isTablet: isTablet)
                        // Use local sizes so moving the surface cannot alter its
                        // center through transformed coordinate-space origins.
                        let headerHeight = surface.size.height - geometry.size.height
                        let center = viewportCenterY.map { $0 - headerHeight }
                        NowPlayingStage(viewport: geometry.size, isTablet: isTablet, centerY: center) {
                            cover.measurePlayerFrame(cover: true, in: Space.surface)
                            controls(style: style, width: width)
                        }
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Space.viewport)).minY } action: { scrollTop = $0 }
                    }.scrollBounceBehavior(.basedOnSize).background(Theme.background)
                        .coordinateSpace(name: Space.viewport)
                        .modifier(PlayerSwipe(enabled: scrollTop >= -1 && !scrubbing,
                            acceptsStart: hitRegions.accepts))
                        .accessibilityIdentifier("player.scroll")
                }
            }
            .coordinateSpace(name: Space.surface)
            .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { hitRegions.origin = $0 }
            .background(Theme.background)
            .sheet(item: $sharing) { ActivitySheet(selection: $0).modifier(AppAppearance()) }
            .sheet(isPresented: $queueVisible) { QueueView(player: player).modifier(AppAppearance()) }
            .sheet(item: $creditsSheet, onDismiss: finishArtistSelection) { selection in
                PlaybackCreditsSheet(credits: selection.credits) { name in
                    guard selection.id == player.current?.id else { return }
                    pendingArtist = (selection.id, name)
                    creditsSheet = nil
                }.modifier(AppAppearance())
            }
            .onChange(of: player.current?.id) { _, _ in
                pendingArtist = nil
                creditsSheet = nil
            }
        }.tint(Theme.accent)
            .accessibilityAction(.escape) { player.isExpanded = false }
    }

    private var header: some View {
        HStack(spacing: 20) {
            IconButton(symbol: "chevron.down", label: L10n.text("mobile.collapse")) { player.isExpanded = false }
                .background(Theme.surface, in: Circle()).accessibilityIdentifier("player.collapse")
            Spacer(minLength: 0)
            if let title = player.current?.albumTitle, !title.isEmpty, player.current?.albumId != nil {
                Button(action: openAlbum) {
                    Text(title).font(Theme.body(13)).foregroundStyle(Theme.dim).lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("player.album")
                    .accessibilityHint(L10n.text("player.viewAlbum"))
            } else {
                Text(L10n.text("mobile.nowPlaying"))
                    .font(Theme.body(13)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
            Menu {
                if let track = player.current {
                    if let selection = ShareSelection.track(track, client: model.imageClient) {
                        Button(L10n.text("mobile.shareTrack"), systemImage: "square.and.arrow.up") { sharing = selection }
                            .accessibilityIdentifier("player.share")
                        Divider()
                    }
                    TrackActions(track: track, model: model)
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.ink).frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle()).contentShape(Circle())
            }.accessibilityLabel(L10n.text("mobile.moreActions")).accessibilityIdentifier("player.more")
        }
        .padding(.horizontal, isTablet ? 32 : 20)
        .padding(.top, isTablet ? 24 : 12).padding(.bottom, isTablet ? 16 : 8)
        .contentShape(Rectangle()).modifier(PlayerSwipe())
    }

    private struct CreditsSelection: Identifiable {
        let id: String
        let credits: PlaybackCredits
    }

    private func openAlbum() {
        if let album = player.current?.albumId { model.pendingRoute = .album(album) }
    }

    private func openArtists() {
        guard let track = player.current else { return }
        let credits = PlaybackCredits(track: track)
        if let name = credits.singleArtist { model.pendingRoute = .artist(name) }
        else if !credits.isEmpty { creditsSheet = CreditsSelection(id: track.id, credits: credits) }
    }

    private func finishArtistSelection() {
        // Dismiss the nested sheet before the shell closes Now Playing and routes.
        let selection = pendingArtist
        pendingArtist = nil
        if let selection, selection.trackID == player.current?.id {
            model.pendingRoute = .artist(selection.name)
        }
    }

    private var cover: some View {
        Cover(albumID: player.current?.albumId ?? "", size: 800, client: model.imageClient)
            .clipShape(RoundedRectangle(cornerRadius: isTablet ? 18 : 14))
            .shadow(color: .black.opacity(isTablet ? 0.12 : 0), radius: 22, x: 0, y: 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(player.current?.albumTitle ?? "")
            .accessibilityAddTraits(.isImage).accessibilityIdentifier("player.cover")
    }

    private var favoriteButton: PersonalFavoriteButton? {
        guard let track = player.current else { return nil }
        return PersonalFavoriteButton(track: track, favorites: model.personalFavorites)
    }

    private func controls(style: NowPlayingLayout.ControlStyle, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: style.spacing) {
            NowPlayingHeading(track: player.current, openAlbum: openAlbum,
               openArtists: openArtists, personalFavorite: favoriteButton,
               titleSize: style.titleSize, artistSize: style.artistSize)
                .measurePlayerFrame(cover: false, in: Space.surface)
                .environment(\.marqueeSuspended, transitioning || routePickerPresented || queueVisible || creditsSheet != nil || sharing != nil)
            PlayerTimeline(player: player, style: style, scrubbing: $scrubbing)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Space.surface)).insetBy(dx: -12, dy: -12) } action: { hitRegions.seek = $0 }
            HStack(spacing: 0) {
                ShuffleToggle(player: player, identifier: "player.shuffle")
                Spacer(minLength: 4)
                IconButton(symbol: "backward.end.fill", label: L10n.text("player.prev"), symbolSize: style.skipSize) { player.previous() }
                Spacer(minLength: 4)
                PlayButton(player: player, diameter: style.playDiameter)
                Spacer(minLength: 4)
                IconButton(symbol: "forward.end.fill", label: L10n.text("player.next"), symbolSize: style.skipSize) { player.next() }
                    .accessibilityIdentifier("player.next")
                Spacer(minLength: 4)
                IconButton(symbol: player.queue.repeatMode == .one ? "repeat.1" : "repeat",
                           label: L10n.text(["player.repeatOff", "player.repeatAll", "player.repeatOne"][player.queue.repeatMode.rawValue]),
                           selected: player.queue.repeatMode != .off) { player.cycleRepeat() }
            }.padding(.vertical, 4)
                .frame(width: min(width, style.transportWidth)).frame(maxWidth: .infinity)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Space.surface)) } action: { hitRegions.transport = $0 }
            // Icons only, under shuffle and repeat, as in the system music app.
            HStack {
                RoutePicker { routePickerPresented = $0 }
                    .frame(width: 44, height: 44).accessibilityLabel(L10n.text("mobile.audioOutput"))
                    .accessibilityIdentifier("player.route")
                    .accessibilityValue(L10n.text(routePickerPresented ? "mobile.expanded" : "mobile.collapsed"))
                Spacer()
                IconButton(symbol: "list.bullet", label: L10n.text("mobile.queue")) { queueVisible = true }
                    .accessibilityIdentifier("player.queue")
            }.frame(width: min(width, style.transportWidth)).frame(maxWidth: .infinity)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Space.surface)) } action: { hitRegions.footer = $0 }
            if let error = player.error {
                VStack(alignment: .leading, spacing: 10) {
                    Text(error).font(Theme.body(14)).foregroundStyle(Theme.dim)
                    Button(L10n.text("common.retry")) { player.resume() }
                }
            }
        }
    }
}

// Observe the audio clock only here. Its half-second updates must not measure
// artwork, redraw the heading or rebuild the moving player surface.
private struct PlayerTimeline: View {
    let player: PlayerModel
    let style: NowPlayingLayout.ControlStyle
    @Binding var scrubbing: Bool
    @State private var scrubTime: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            Slider(value: Binding(get: { scrubbing ? scrubTime : min(player.elapsed, max(player.duration, 1)) },
                                  set: { scrubTime = $0 }),
                   in: 0...max(player.duration, 1), onEditingChanged: { editing in
                if editing { scrubTime = player.elapsed; scrubbing = true }
                else { scrubbing = false; player.seek(to: scrubTime) }
            }).tint(style == .compact ? Theme.accent : Theme.ink)
                .disabled(player.isLoading).accessibilityLabel(L10n.text("player.seek"))
                .accessibilityIdentifier("player.seek")
            HStack {
                Text(timestamp(scrubbing ? scrubTime : player.elapsed))
                Spacer()
                if player.isLoading || player.isSeeking {
                    Text(L10n.text("mobile.preparing")).accessibilityIdentifier("player.buffering")
                }
                Spacer()
                Text("−" + timestamp(max(0, player.duration - (scrubbing ? scrubTime : player.elapsed))))
            }.font(Theme.body(style.timeSize)).monospacedDigit().foregroundStyle(Theme.faint)
        }
    }
}

struct QueueView: View {
    let player: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var editMode = EditMode.inactive
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L10n.text("mobile.queue")).displayFont(30).foregroundStyle(Theme.ink)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                }
                if let current = player.current {
                    Section { QueueTrackRow(track: current).foregroundStyle(Theme.accent).listRowBackground(Theme.surface) } header: { header(L10n.text("mobile.nowPlaying")) }
                }
                Section {
                    let rows = player.queue.upcomingRows
                    ForEach(rows) { row in
                        Button { player.jumpToUpcoming(row.id) } label: { QueueTrackRow(track: track(for: row, in: rows)) }
                            .buttonStyle(.plain).listRowBackground(Theme.background).accessibilityIdentifier("queue.\(row.offset)")
                    }
                    .onMove { source, destination in
                        let ids = source.filter { rows.indices.contains($0) }.map { rows[$0].id }
                        let anchor = rows.indices.contains(destination) ? rows[destination].id : nil
                        player.moveUpcoming(entries: ids, before: anchor)
                    }
                    .onDelete { source in
                        player.removeUpcoming(entries: source.filter { rows.indices.contains($0) }.map { rows[$0].id })
                    }
                } header: { header(L10n.text("mobile.upNext")) }
            }.scrollContentBackground(.hidden).background(Theme.background)
                .accessibilityIdentifier("queue.list")
                .environment(\.editMode, $editMode)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(L10n.text(editMode.isEditing ? "common.done" : "common.edit")) {
                            // Only the edit-mode transition is nonanimated. Keep
                            // native move/delete animations and stable entry IDs.
                            var transaction = Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) { editMode = editMode.isEditing ? .inactive : .active }
                        }.accessibilityIdentifier("queue.edit")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        IconButton(symbol: "xmark", label: L10n.text("common.close")) { dismiss() }
                            .accessibilityIdentifier("queue.close")
                    }
                }
        }.tint(Theme.accent)
    }
    private func header(_ text: String) -> some View {
        Text(text).font(Theme.body(12)).foregroundStyle(Theme.faint).textCase(nil)
    }

    private func track(for row: PlaybackQueue.UpcomingRows.Row, in rows: PlaybackQueue.UpcomingRows) -> Track {
        #if DEBUG
        Self.rowTrackLookups += 1
        #endif
        return rows.track(at: row.offset)
    }

    #if DEBUG
    // Counts actual row materialization in the native large-queue regression.
    static var rowTrackLookups = 0
    #endif
}

// Editing narrows a List row to make room for delete and reorder controls.
// Keep both text lines stable across that width change, without fixing their
// point height or preventing Dynamic Type from growing them.
struct QueueTrackRow: View {
    let track: Track

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(track.title).font(Theme.body(15)).lineLimit(1)
            Text(PlaybackCredits(track: track).compactText).font(Theme.body(12))
                .foregroundStyle(Theme.dim).lineLimit(1)
        }.fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(track.title + ", " + PlaybackCredits(track: track).fullText)
    }
}

struct RoutePicker: UIViewRepresentable {
    var onPresentationChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(onPresentationChange: onPresentationChange) }

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(Theme.dim)
        view.activeTintColor = UIColor(Theme.accent)
        view.prioritizesVideoDevices = false
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        context.coordinator.onPresentationChange = onPresentationChange
    }
    static func dismantleUIView(_ uiView: AVRoutePickerView, coordinator: Coordinator) { uiView.delegate = nil }

    @MainActor
    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        var onPresentationChange: (Bool) -> Void

        init(onPresentationChange: @escaping (Bool) -> Void) { self.onPresentationChange = onPresentationChange }

        // AVKit's Objective-C delegate requirements are nonisolated. Only the
        // presentation flag crosses this boundary; the view is not captured.
        nonisolated func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            Task { @MainActor [weak self] in self?.onPresentationChange(true) }
        }
        nonisolated func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            Task { @MainActor [weak self] in self?.onPresentationChange(false) }
        }
    }
}
