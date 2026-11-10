import SwiftUI

struct CatalogTrackRow: View {
    let track: Track
    let model: AppModel
    var showCover = true
    // When set, the row shows a track number instead of a cover.
    var number: Int?
    // Album pages hide the credit line when it repeats the album artist.
    var hideArtist = false
    var identifier: String?
    let play: () -> Void

    private var isCurrent: Bool { model.player.current?.id == track.id }

    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                if let number {
                    Group {
                        if isCurrent { Image(systemName: "waveform").foregroundStyle(Theme.accent) }
                        else { Text(String(number)).foregroundStyle(.secondary) }
                    }.font(Theme.body(15).monospacedDigit()).frame(width: 26)
                } else if showCover {
                    Cover(albumID: track.albumId ?? "", size: 160, client: model.imageClient)
                        .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(Theme.body(17)).foregroundStyle(isCurrent ? Theme.accent : Theme.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    if !hideArtist {
                        Text(track.artist ?? "").font(Theme.body(12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                FavoriteBadges(kind: .track, id: track.id, model: model)
                if model.downloads?.records[track.id]?.state == .done {
                    Image(systemName: "arrow.down.circle.fill").font(Theme.body(12)).foregroundStyle(.secondary)
                        .accessibilityLabel(L10n.text("mobile.downloaded"))
                }
                Text(timestamp(track.duration ?? 0)).font(Theme.body(12).monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.vertical, 4).frame(minHeight: hideArtist ? 44 : 52).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier(identifier ?? "track.\(track.id)")
            .contextMenu { TrackActions(track: track, model: model, play: play) }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { model.player.enqueue([track], next: true) } label: {
                    Label(L10n.text("mobile.playNext"), systemImage: "text.line.first.and.arrowtriangle.forward")
                }.tint(Theme.accent)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button { model.player.enqueue([track], next: false) } label: {
                    Label(L10n.text("mobile.addToQueue"), systemImage: "text.badge.plus")
                }
            }
    }
}

struct TrackActions: View {
    let track: Track
    let model: AppModel
    var play: (() -> Void)?
    var body: some View {
        if let play { Button(L10n.text("common.play"), systemImage: "play", action: play) }
        Button(L10n.text("mobile.playNext"), systemImage: "text.line.first.and.arrowtriangle.forward") {
            model.player.enqueue([track], next: true)
        }
        Button(L10n.text("mobile.addToQueue"), systemImage: "text.badge.plus") {
            model.player.enqueue([track], next: false)
        }
        if let downloads = model.downloads {
            if downloads.records[track.id] != nil {
                Button(L10n.text("mobile.removeDownload"), systemImage: "trash") { downloads.remove(track.id) }
            } else {
                Button(L10n.text("mobile.download"), systemImage: "arrow.down.circle") { Task { await model.download(track) } }
            }
        }
        Section {
            let saved = model.personalFavorites.contains(.track, id: track.id)
            Button(L10n.text(saved ? "personal.remove" : "personal.add"), systemImage: saved ? "heart.slash" : "heart") {
                let token = model.personalFavorites.revision
                Task {
                    guard token == model.personalFavorites.revision else { return }
                    await model.personalFavorites.toggle(track: track)
                }
            }.disabled(!model.personalFavorites.isReady || model.personalFavorites.loading || model.personalFavorites.busy)
                .accessibilityIdentifier("personal.track.\(track.id)")
            if model.sessionStore.isAdmin {
                let picked = model.favorites.contains(.track, id: track.id)
                Button(L10n.text(picked ? "personal.curatedRemove" : "personal.curatedAdd"), systemImage: "sparkles") {
                    let session = model.sessionStore.revision
                    Task {
                        guard model.signedIn, session == model.sessionStore.revision else { return }
                        await model.favorites.toggle(.track, id: track.id)
                    }
                }.disabled(model.favorites.busy)
                    .accessibilityIdentifier("curated.track.\(track.id)")
            }
        }
        Section {
            if let album = track.albumId {
                Button(L10n.text("player.viewAlbum"), systemImage: "square.stack") { model.pendingRoute = .album(album) }
            }
            ForEach(track.credits.filter { !$0.name.isEmpty }, id: \.name) { credit in
                Button(credit.name, systemImage: "person") { model.pendingRoute = .artist(credit.name) }
            }
        }
    }
}

struct CatalogProblem: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.circle").font(Theme.body(15))
            Button(L10n.text("common.retry"), action: retry)
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionHeading: View {
    let title: String
    var count: Int?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).displayFont(22, relativeTo: .title2).foregroundStyle(Theme.ink)
            Spacer()
            if let count { Text(String(count)).font(Theme.body(12).monospacedDigit()).foregroundStyle(.secondary) }
        }.accessibilityAddTraits(.isHeader)
    }
}
