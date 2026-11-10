import SwiftUI

struct AlbumView: View {
    let model: AppModel
    let albumID: String
    @State private var album: Album?
    @State private var error: String?
    @State private var readingNote = false
    @State private var noteDocument: MarkdownDocument?
    @State private var expandedDescriptors = false
    @State private var gallery: String?
    @State private var editing = false
    @State private var sharing: ShareSelection?
    @State private var confirmDelete = false
    @State private var working = false
    // Failures only; a successful write shows itself in the page.
    @State private var notice: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if let album {
                    let layout = AlbumHeaderLayout(width: min(1000, geometry.size.width) - 40,
                                                   accessibility: textSize.isAccessibilitySize)
                    VStack(alignment: .leading, spacing: layout.usesColumns ? 40 : 28) {
                        Group {
                            if layout.usesColumns {
                                HStack(alignment: .center, spacing: layout.spacing) {
                                    cover(album).frame(width: layout.coverSide, height: layout.coverSide)
                                    header(album, layout: layout).frame(width: layout.informationWidth)
                                }.frame(width: layout.width)
                            } else {
                                VStack(spacing: layout.spacing) {
                                    cover(album).frame(width: layout.coverSide, height: layout.coverSide)
                                    header(album, layout: layout).frame(width: layout.informationWidth)
                                }
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, layout.usesColumns ? 16 : 0)
                        trackList(album)
                        details(album)
                    }.padding(.horizontal, 20).padding(.vertical, 16).frame(maxWidth: 1000).frame(maxWidth: .infinity)
                } else if let error {
                    ContentUnavailableView {
                        Label(L10n.text("common.loadFailed"), systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button(L10n.text("common.retry")) { Task { await load() } }
                    }
                } else { ProgressView().frame(maxWidth: .infinity).padding(80) }
            }.accessibilityIdentifier("album.scroll")
        }
        .background(Theme.background).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Personal favorites stay separate from admin picks in the menu.
            ToolbarItem(placement: .topBarTrailing) {
                if let album { favoriteButton(album) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let album {
                    Menu {
                        if let selection = ShareSelection.album(album, client: model.imageClient) {
                            Button(L10n.text("mobile.shareAlbum"), systemImage: "square.and.arrow.up") { sharing = selection }
                                .accessibilityIdentifier("album.share")
                            Divider()
                        }
                        AlbumActions(album: album, model: model)
                        if model.sessionStore.isAdmin && !model.demo { adminActions(album) }
                    } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel(L10n.text("mobile.moreActions")).accessibilityIdentifier("album.menu")
                        .disabled(working)
                }
            }
        }
        .sheet(item: $sharing) { ActivitySheet(selection: $0).modifier(AppAppearance()) }
        .refreshable { await load(refresh: true) }
        .task(id: albumID) { await load() }
        .task(id: album?.note) {
            guard let source = album?.note, !source.isEmpty else { noteDocument = nil; return }
            let prepared = await MarkdownDocument.prepare(source)
            if !Task.isCancelled { noteDocument = prepared }
        }
        .onChange(of: albumID) { _, _ in expandedDescriptors = false }
        .sheet(item: Binding(get: { gallery.map(GallerySelection.init) }, set: { gallery = $0?.id })) { selection in
            GalleryViewer(images: album?.images ?? [], client: model.imageClient, selection: selection.id)
        }
        .sheet(isPresented: $readingNote) {
            if let album, let note = album.note {
                MarkdownReaderSheet(title: album.title, text: note)
            }
        }
        .sheet(isPresented: $editing) {
            if let album {
                AlbumEditView(model: model, album: album) { Task { await load() } }
            }
        }
        .confirmationDialog(L10n.text("albumPage.deleteTitle"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L10n.text("albumPage.deleteKeep"), role: .destructive) { Task { await delete(files: false) } }
            Button(L10n.text("albumPage.deleteFiles"), role: .destructive) { Task { await delete(files: true) } }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: { Text(L10n.text("albumPage.deleteBody")) }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(L10n.text("common.done"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private func adminActions(_ album: Album) -> some View {
        Section(L10n.text("mobile.manage")) {
            Button(L10n.text("albumPage.edit"), systemImage: "pencil") { editing = true }
            Button(L10n.text(album.hidden == true ? "albumPage.unhide" : "albumPage.hide"),
                   systemImage: album.hidden == true ? "eye" : "eye.slash") { Task { await toggleHidden(album) } }
            Button(L10n.text("common.delete"), systemImage: "trash", role: .destructive) { confirmDelete = true }
        }
    }

    private func toggleHidden(_ album: Album) async {
        guard !working else { return }
        working = true
        defer { working = false }
        let next = album.hidden != true
        do {
            try await model.catalog.setHidden(album.id, hidden: next)
            // Without Show Hidden the album leaves the library, so its page closes too.
            if next && !model.catalog.showHidden { dismiss(); return }
            self.album = try await model.catalog.album(album.id, refresh: true)
        } catch is CancellationError {
        } catch {
            notice = L10n.text("albumPage.hideFail", error.localizedDescription)
        }
    }

    // Deletion is irreversible, so a second request is never sent while one is running.
    private func delete(files: Bool) async {
        guard !working, let album else { return }
        working = true
        defer { working = false }
        do {
            try await model.deleteAlbum(album.id, files: files)
            dismiss()
        } catch is CancellationError {
        } catch {
            notice = L10n.text("albumPage.deleteFail", error.localizedDescription)
        }
    }

    private func cover(_ album: Album) -> some View {
        Cover(albumID: album.id, size: 800, revision: album.updatedAt, client: model.imageClient)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .ignore).accessibilityLabel(album.title)
            .accessibilityAddTraits(.isImage).accessibilityIdentifier("album.cover")
    }

    private func header(_ album: Album, layout: AlbumHeaderLayout) -> some View {
        VStack(spacing: layout.usesColumns ? 14 : 10) {
            Text(album.title).displayFont(layout.titleSize).fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("album.title")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { artistCredits(album, separated: true) }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(spacing: 4) { artistCredits(album, separated: false) }
            }.font(Theme.body(layout.usesColumns ? 19 : 17)).foregroundStyle(Theme.dim)
            FlowLayout(spacing: 12, centered: true) {
                if let year = album.year, year > 0 { Text(String(year)) }
                Text(L10n.count("count.tracks", album.normalizedTracks.count))
                if let duration = album.duration, duration > 0 { Text(timestamp(duration)) }
                if album.hidden == true { Label(L10n.text("albumPage.hiddenBadge"), systemImage: "eye.slash") }
            }.font(Theme.body(13).monospacedDigit()).foregroundStyle(Theme.faint)
            formatSummary(album)
            if let rym = album.rym, let rating = rym.validRating {
                AlbumRatingLine(rym: rym, rating: rating, centered: true)
            }
            controls(album, diameter: layout.playDiameter)
                .padding(.top, layout.usesColumns ? 12 : 6)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func artistCredits(_ album: Album, separated: Bool) -> some View {
        ForEach(Array(album.credits.enumerated()), id: \.offset) { index, credit in
            NavigationLink(value: CatalogRoute.artist(credit.name)) {
                Text(credit.name + (separated && index < album.credits.count - 1 ? " ·" : ""))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.buttonStyle(.plain)
                .accessibilityIdentifier("album.artist.\(index)")
        }
    }

    // Shuffle, Play all, Download: icons only and symmetric about the play
    // button. Shuffle is a mode; Play all applies it.
    private func controls(_ album: Album, diameter: CGFloat) -> some View {
        HStack(spacing: diameter > 60 ? 36 : 28) {
            ShuffleToggle(player: model.player, identifier: "album.shuffle")
            Button { model.player.play(album.normalizedTracks) } label: {
                Image(systemName: "play.fill").font(.system(size: diameter * 0.36, weight: .semibold)).foregroundStyle(Theme.onAccent)
                    .frame(width: diameter, height: diameter).background(Theme.accent, in: Circle())
                    .contentShape(Circle())
            }.buttonStyle(.plain).accessibilityLabel(L10n.text("common.playAll")).accessibilityIdentifier("album.play")
            // An empty slot keeps the play button centred where downloads are unavailable.
            if let downloads = model.downloads { AlbumDownloadButton(album: album, downloads: downloads) }
            else { Color.clear.frame(width: 44, height: 44).accessibilityHidden(true) }
        }.disabled(album.normalizedTracks.isEmpty)
    }

    @ViewBuilder
    private func favoriteButton(_ album: Album) -> some View {
        let faved = model.personalFavorites.contains(.album, id: album.id)
        Button {
            let token = model.personalFavorites.revision
            Task {
                guard token == model.personalFavorites.revision else { return }
                await model.personalFavorites.toggle(album: album)
            }
        } label: {
            Image(systemName: faved ? "heart.fill" : "heart").foregroundStyle(faved ? Theme.accent : Theme.ink)
                .frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel(L10n.text(faved ? "personal.remove" : "personal.add"))
            .accessibilityValue(L10n.text(faved ? "personal.saved" : "personal.notSaved"))
            .accessibilityAddTraits(faved ? .isSelected : [])
            .disabled(!model.personalFavorites.isReady || model.personalFavorites.loading || model.personalFavorites.busy)
            .accessibilityIdentifier("album.personalFavorite")
    }

    private func trackList(_ album: Album) -> some View {
        let tracks = album.normalizedTracks
        let multiDisc = Set(tracks.map { $0.disc ?? 1 }).count > 1
        return LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                if multiDisc && (index == 0 || track.disc != tracks[index - 1].disc) {
                    Text(L10n.text("common.disc", String(track.disc ?? 1)))
                        .font(Theme.body(13, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, index == 0 ? 0 : 18).padding(.bottom, 6)
                }
                CatalogTrackRow(track: track, model: model, number: track.track ?? index + 1,
                                hideArtist: track.artist == album.artist, identifier: "track.\(index)") {
                    model.player.play(tracks, index: index)
                }
                Divider().overlay(Theme.line)
            }
        }
    }

    @ViewBuilder
    private func details(_ album: Album) -> some View {
        let primary = album.genres ?? album.rym?.genres ?? []
        let secondary = album.secondaryGenres ?? album.rym?.secondaryGenres ?? []
        let descriptors = album.rym?.descriptors ?? []
        if !primary.isEmpty || !secondary.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: L10n.text("common.genres"))
                FlowLayout {
                    ForEach(primary, id: \.self) { genre in
                        NavigationLink(value: CatalogRoute.genre(genre)) { Chip(text: genre, prominent: true) }.buttonStyle(.plain)
                    }
                    ForEach(secondary, id: \.self) { genre in
                        NavigationLink(value: CatalogRoute.genre(genre)) { Chip(text: genre) }.buttonStyle(.plain)
                    }
                }
            }
        }
        if !descriptors.isEmpty {
            AlbumDescriptors(descriptors: descriptors, isExpanded: $expandedDescriptors)
        }
        if let note = album.note?.nonEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: L10n.text("albumPage.note"))
                if let document = noteDocument, document.source == note {
                    Text(document.plainPreview).font(Theme.body(16)).foregroundStyle(Theme.dim).lineSpacing(4)
                        .lineLimit(6).accessibilityIdentifier("album.note.preview")
                } else { ProgressView() }
                Button(L10n.text("md.expand")) { readingNote = true }.accessibilityIdentifier("album.note.read")
            }
        }
        if let images = album.images, !images.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: L10n.text("albumPage.gallery"), count: images.count)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(images, id: \.self) { id in
                            Button { gallery = id } label: {
                                RemoteArtwork(url: model.imageClient?.imageURL(id, size: 400), client: model.imageClient, pixels: 400)
                                    .frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).accessibilityLabel(L10n.text("common.zoom"))
                                .accessibilityIdentifier("gallery.\(id)")
                        }
                    }
                }
            }
        }
        if let similar = album.similar, !similar.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: L10n.text("albumPage.similar"))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(similar) { item in
                            NavigationLink(value: CatalogRoute.album(item.id)) {
                                SimilarAlbumCard(album: item, client: model.imageClient)
                            }.buttonStyle(.plain).accessibilityIdentifier("similar.\(item.id)")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func formatSummary(_ album: Album) -> some View {
        let tracks = album.normalizedTracks
        let formats = Array(Set(tracks.compactMap { $0.format?.uppercased().nonEmpty })).sorted()
        let bytes = tracks.compactMap(\.size).reduce(0, +)
        if !formats.isEmpty || bytes > 0 {
            FlowLayout(spacing: 10, centered: true) {
                ForEach(formats, id: \.self) { Text($0) }
                if bytes > 0 { Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
            }.font(Theme.body(13).monospacedDigit()).foregroundStyle(Theme.faint)
                .accessibilityElement(children: .combine).accessibilityIdentifier("album.format")
        }
    }

    private func load(refresh: Bool = false) async {
        error = nil
        do { album = try await model.catalog.album(albumID, refresh: refresh) }
        catch is CancellationError { return }
        catch { if album == nil { self.error = error.localizedDescription } }
    }
}

// A fixed square anchors the recommendation row; text may grow with Dynamic
// Type, but long titles never borrow height from the cover or wrap to two lines.
struct SimilarAlbumCard: View {
    let album: SimilarAlbum
    var client: APIClient?
    static let coverSide: CGFloat = 136

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Cover(albumID: album.id, size: 480, client: client)
                .frame(width: Self.coverSide, height: Self.coverSide)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(album.title).font(Theme.body(15)).foregroundStyle(Theme.ink)
                .lineLimit(1).truncationMode(.tail)
                .accessibilityIdentifier("similar.title.\(album.id)")
            Text(album.artist ?? "").font(Theme.body(12)).foregroundStyle(.secondary).lineLimit(1)
                .accessibilityIdentifier("similar.artist.\(album.id)")
        }.frame(width: Self.coverSide, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GallerySelection: Identifiable { let id: String }
