import SwiftUI

// Only structured credits identify individual artists. A display string may
// contain commas or ampersands within a band's name, so it is never split.
struct PlaybackCredits: Equatable, Sendable {
    let names: [String]
    let rawText: String

    init(track: Track?) {
        var seen: Set<String> = []
        names = (track?.artists ?? []).compactMap { credit in
            let name = credit.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return name
        }
        rawText = track?.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var isEmpty: Bool { names.isEmpty && rawText.isEmpty }
    var firstName: String { names.first ?? rawText }
    var additionalCount: Int { max(0, names.count - 1) }
    var singleArtist: String? { names.count == 1 ? names.first : nil }
    var fullText: String { names.isEmpty ? rawText : names.joined(separator: " · ") }
    var moreText: String { L10n.text("mobile.moreArtists", String(additionalCount)) }
    var summarizesNames: Bool { names.count > 3 }
    var displayNames: String { summarizesNames ? firstName : fullText }
    var compactText: String { summarizesNames ? firstName + " · " + moreText : fullText }
}

struct PlaybackCreditsButton: View {
    let credits: PlaybackCredits
    let action: () -> Void
    var fontSize: CGFloat = 17

    var body: some View {
        if !credits.isEmpty {
            Button(action: action) {
                HStack(spacing: 8) {
                    Text(credits.displayNames)
                        .lineLimit(credits.names.count > 1 && !credits.summarizesNames ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if credits.summarizesNames {
                        Text(credits.moreText).fixedSize()
                            .accessibilityIdentifier("player.artists.count")
                    }
                    if credits.summarizesNames || credits.names.isEmpty {
                        Image(systemName: "chevron.right").font(Theme.body(12, weight: .semibold)).accessibilityHidden(true)
                    }
                }.font(Theme.body(fontSize)).foregroundStyle(Theme.dim)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("player.artist")
                .accessibilityLabel(credits.fullText)
                .accessibilityValue(credits.summarizesNames ? credits.moreText : "")
                .accessibilityHint(L10n.text(credits.singleArtist == nil ? "mobile.viewCredits" : "mobile.viewArtist"))
        }
    }
}

struct NowPlayingHeading: View {
    let track: Track?
    let openAlbum: () -> Void
    let openArtists: () -> Void
    var favorite: PlayerFavoriteButton? = nil
    var personalFavorite: PersonalFavoriteButton? = nil
    var titleSize: CGFloat = 27
    var artistSize: CGFloat = 17

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                PlaybackTitleButton(track: track, openAlbum: openAlbum, fontSize: titleSize)
                if let personalFavorite { personalFavorite.id(track?.id).fixedSize() }
                else if let favorite { favorite.id(track?.id).fixedSize() }
            }
            PlaybackCreditsButton(credits: PlaybackCredits(track: track), action: openArtists, fontSize: artistSize)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlaybackCreditsSheet: View {
    let credits: PlaybackCredits
    let selectArtist: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if credits.names.isEmpty {
                    Text(credits.rawText).font(Theme.body(17)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .listRowBackground(Theme.surface).accessibilityIdentifier("player.credits.raw")
                } else {
                    ForEach(Array(credits.names.enumerated()), id: \.element) { index, name in
                        Button { selectArtist(name) } label: {
                            HStack(spacing: 12) {
                                Text(name).font(Theme.body(17)).foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(Theme.body(12)).foregroundStyle(Theme.dim)
                                    .accessibilityHidden(true)
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).listRowBackground(Theme.surface)
                            .accessibilityIdentifier("player.credit.\(index)")
                            .accessibilityHint(L10n.text("mobile.viewArtist"))
                    }
                }
            }.scrollContentBackground(.hidden).background(Theme.background)
                .navigationTitle(L10n.text("nav.artists")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.text("common.done")) { dismiss() }.accessibilityIdentifier("player.credits.done")
                    }
                }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible).tint(Theme.accent)
    }
}
