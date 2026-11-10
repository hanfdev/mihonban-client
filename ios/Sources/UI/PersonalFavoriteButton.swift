import SwiftUI

struct PersonalFavoriteButton: View {
    let track: Track
    let favorites: PersonalFavoritesStore

    var body: some View {
        let selected = favorites.contains(.track, id: track.id)
        Button {
            let token = favorites.revision
            Task {
                guard token == favorites.revision else { return }
                await favorites.toggle(track: track)
            }
        } label: {
            Image(systemName: selected ? "heart.fill" : "heart")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(selected ? Theme.accent : Theme.dim)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!favorites.isReady || favorites.loading || favorites.busy)
            .accessibilityIdentifier("player.personalFavorite")
            .accessibilityLabel(L10n.text(selected ? "personal.remove" : "personal.add"))
            .accessibilityValue(L10n.text(selected ? "personal.saved" : "personal.notSaved"))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct FavoriteBadges: View {
    let kind: FavoriteKind
    let id: String
    let model: AppModel
    var onCover = false

    var body: some View {
        let personal = model.personalFavorites.contains(kind, id: id)
        let curated = model.favorites.contains(kind, id: id)
        if personal || curated {
            HStack(spacing: 6) {
                if personal { Image(systemName: "heart.fill").accessibilityLabel(L10n.text("personal.saved")) }
                if curated { Image(systemName: "sparkles").accessibilityLabel(L10n.text("personal.curatedTitle")) }
            }.font(Theme.body(12)).foregroundStyle(Theme.accent)
                .padding(onCover ? 7 : 0)
                .background { if onCover { Capsule().fill(.regularMaterial) } }
                .padding(onCover ? 6 : 0)
        }
    }
}
