import SwiftUI

// The caller keys this view by track ID so a late error for an old track cannot
// appear on the next track. The write itself always targets the captured ID.
struct PlayerFavoriteButton: View {
    let trackID: String
    let favorites: FavoritesStore
    let session: SessionStore
    @State private var submitting = false
    @State private var notice: String?

    var body: some View {
        if session.isAdmin {
            let selected = favorites.contains(.track, id: trackID)
            Button {
                guard session.isAdmin, !submitting, !favorites.busy else { return }
                submitting = true
                let token = session.revision
                Task {
                    guard token == session.revision else { submitting = false; return }
                    await favorites.toggle(.track, id: trackID)
                    submitting = false
                    if token == session.revision { notice = favorites.error }
                }
            } label: {
                Image(systemName: selected ? "sparkles" : "sparkle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(selected ? Theme.accent : Theme.dim)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(submitting || favorites.busy)
                .accessibilityIdentifier("player.favorite")
                .accessibilityLabel(L10n.text(selected ? "personal.curatedRemove" : "personal.curatedAdd"))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                    Button(L10n.text("common.done"), role: .cancel) { notice = nil }
                }
                .onChange(of: session.revision) { _, _ in notice = nil }
        }
    }
}
