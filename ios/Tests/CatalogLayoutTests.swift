import SwiftUI
import XCTest
@testable import Mihonban

// Measures catalog views as laid out, so alignment rules are checked without screenshots.
@MainActor
final class CatalogLayoutTests: XCTestCase {
    private func size<V: View>(_ view: V, width: CGFloat) -> CGSize {
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private func album(_ title: String, rating: Double?) -> Album {
        var album = Album(id: "a", title: title, artist: "Fishmans", year: 1999)
        if let rating { album.rym = RymRating(rating: rating, votes: 10) }
        return album
    }

    func testTileCaptionsLineUpAcrossARow() {
        let short = size(AlbumCaption(album: album("Ok", rating: 4.4)), width: 170).height
        let wrapped = size(AlbumCaption(album: album("Songs in the Key of Life", rating: 4.32)), width: 170).height
        let long = size(AlbumCaption(album: album(String(repeating: "Long Season ", count: 12), rating: nil)), width: 170).height
        let unrated = size(AlbumCaption(album: album("Ok", rating: nil)), width: 170).height
        XCTAssertGreaterThan(short, 0)
        XCTAssertEqual(short, wrapped, accuracy: 0.5, "all titles occupy exactly one line")
        XCTAssertEqual(short, long, accuracy: 0.5, "overflow truncates without reserving a second line")
        XCTAssertEqual(short, unrated, accuracy: 0.5, "a missing rating does not change the height")
        var undated = album("Ok", rating: nil)
        undated.year = nil
        XCTAssertEqual(short, size(AlbumCaption(album: undated), width: 170).height, accuracy: 0.5)
        for textSize in [DynamicTypeSize.large, .accessibility3] {
            let small = size(AlbumCaption(album: album("Ok", rating: 4)).environment(\.dynamicTypeSize, textSize), width: 170)
            let tall = size(AlbumCaption(album: album(String(repeating: "Long Title ", count: 10), rating: nil))
                .environment(\.dynamicTypeSize, textSize), width: 170)
            XCTAssertEqual(small.height, tall.height, accuracy: 0.5, "text=\(textSize): rating must stay on one line")
            XCTAssertLessThanOrEqual(tall.width, 170.5)
        }
    }

    func testSimilarAlbumCardsKeepOneTitleLineAndAStableSquare() {
        let short = SimilarAlbum(id: "short", artist: "Solo", title: "Letters")
        let long = SimilarAlbum(id: "long", artist: String(repeating: "Studio Ensemble ", count: 12),
                                title: String(repeating: "A quiet room for evening studies ", count: 12))
        for textSize in [DynamicTypeSize.large, .accessibility3, .accessibility5] {
            let baseline = size(SimilarAlbumCard(album: short).environment(\.dynamicTypeSize, textSize), width: 136)
            let overflow = size(SimilarAlbumCard(album: long).environment(\.dynamicTypeSize, textSize), width: 136)
            XCTAssertEqual(overflow.width, 136, accuracy: 0.5)
            XCTAssertEqual(overflow.height, baseline.height, accuracy: 0.5,
                           "long titles and credits cannot wrap or shrink the cover")
            XCTAssertGreaterThan(overflow.height, 136, "text is laid out below the full-height square")
        }
    }

    func testCoverStaysSquareForWideArtwork() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let wide = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        }
        let measured = size(CoverFrame(image: wide), width: 170)
        XCTAssertEqual(measured.width, 170, accuracy: 0.5, "wide artwork must not widen the tile")
        XCTAssertEqual(measured.height, 170, accuracy: 0.5)
        let empty = size(CoverFrame(image: nil), width: 170)
        XCTAssertEqual(empty.width, measured.width, accuracy: 0.5)
        XCTAssertEqual(empty.height, measured.height, accuracy: 0.5)
    }

    func testShuffleControlHasAStableTouchTarget() {
        let off = size(IconButton(symbol: "shuffle", label: "Shuffle", selected: false) {}, width: 100)
        let on = size(IconButton(symbol: "shuffle", label: "Shuffle", selected: true) {}, width: 100)
        XCTAssertEqual(off.width, 44, accuracy: 0.5)
        XCTAssertEqual(off.height, 44, accuracy: 0.5)
        XCTAssertEqual(on.width, off.width, accuracy: 0.5)
        XCTAssertEqual(on.height, off.height, accuracy: 0.5)
    }

    func testArtistRowStaysCompactWithLongAndMultipleCredits() {
        let short = PlaybackCredits(track: Track(id: "s", title: "", artists: [ArtistCredit(name: "Solo")]))
        let many = PlaybackCredits(track: Track(id: "m", title: "", artists:
            (0..<8).map { ArtistCredit(name: String(repeating: "Long artist name ", count: 8) + String($0)) }))
        let raw = PlaybackCredits(track: Track(id: "r", title: "", artist: String(repeating: "Artist, Guest & Ensemble; ", count: 30)))
        for width in [CGFloat(264), 346, 480, 700] {
            for textSize in [DynamicTypeSize.large, .accessibility3] {
                let baseline = size(PlaybackCreditsButton(credits: short) {}.environment(\.dynamicTypeSize, textSize), width: width)
                for credits in [many, raw] {
                    let measured = size(PlaybackCreditsButton(credits: credits) {}.environment(\.dynamicTypeSize, textSize), width: width)
                    XCTAssertEqual(measured.height, baseline.height, accuracy: 0.5)
                    XCTAssertGreaterThanOrEqual(measured.height, 44)
                    XCTAssertLessThanOrEqual(measured.width, width + 0.5)
                }
            }
        }
    }

    func testHeadingKeepsTitleHeightIndependentOfLength() {
        func heading(_ repetitions: Int) -> some View {
            NowPlayingHeading(track: Track(id: "title", title: String(repeating: "Long song title ", count: repetitions),
                                          artist: "Solo"), openAlbum: {}, openArtists: {})
        }
        XCTAssertEqual(size(heading(1), width: 264).height, size(heading(40), width: 264).height, accuracy: 0.5)
        let button = PlaybackTitleButton(track: Track(id: "title", title: "Short", albumId: "album"), openAlbum: {})
        let measured = size(button, width: 264)
        XCTAssertEqual(measured.width, 264, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(measured.height, 44)
    }

    func testFavoriteButtonFitsBesideTheHeading() throws {
        let api = try APIClient(address: "https://example.invalid")
        let session = SessionStore()
        session.connect(api, info: SessionInfo(ok: true, role: "admin", guest: false))
        let store = FavoritesStore(session: session)
        let heart = PlayerFavoriteButton(trackID: "t", favorites: store, session: session)
        let empty = size(heart, width: 100)
        store.replace(Favorites(albums: [], tracks: [FavoriteItem(id: "t")]))
        let selected = size(heart, width: 100)
        XCTAssertEqual(empty.width, 44, accuracy: 0.5)
        XCTAssertEqual(empty.height, 44, accuracy: 0.5)
        XCTAssertEqual(selected.width, empty.width, accuracy: 0.5)
        XCTAssertEqual(selected.height, empty.height, accuracy: 0.5)
        for width in [CGFloat(264), 346, 480] {
            for textSize in [DynamicTypeSize.large, .accessibility3] {
                let track = Track(id: "t", title: String(repeating: "Long song title ", count: 10),
                                  artists: [ArtistCredit(name: "Solo")])
                let heading = NowPlayingHeading(track: track, openAlbum: {}, openArtists: {}, favorite: heart)
                let measured = size(heading.environment(\.dynamicTypeSize, textSize), width: width)
                XCTAssertLessThanOrEqual(measured.width, width + 0.5)
                XCTAssertGreaterThan(measured.height, 44)
            }
        }
        session.connect(api, info: SessionInfo(ok: true, role: "user", guest: false))
        XCTAssertEqual(size(heart, width: 100).height, 0, accuracy: 0.5, "no admin control in a listener's layout")
    }

    func testPersonalFavoriteKeepsItsTouchTargetAndHeadingWidthInBothStates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PersonalFavoritesStore(root: root)
        await store.connect(baseURL: try XCTUnwrap(URL(string: "https://personal-layout.invalid")))
        let track = Track(id: "personal-layout", title: String(repeating: "Long song title ", count: 10),
                          albumId: "personal-album", artists: [ArtistCredit(name: "Solo")])
        let heart = PersonalFavoriteButton(track: track, favorites: store)
        for selected in [false, true] {
            if selected { await store.toggle(track: track) }
            XCTAssertEqual(store.contains(.track, id: track.id), selected)
            let measuredButton = size(heart, width: 100)
            XCTAssertEqual(measuredButton.width, 44, accuracy: 0.5)
            XCTAssertEqual(measuredButton.height, 44, accuracy: 0.5)
            for width in [CGFloat(264), 346, 480] {
                for textSize in [DynamicTypeSize.large, .accessibility3] {
                    let heading = NowPlayingHeading(track: track, openAlbum: {}, openArtists: {}, personalFavorite: heart)
                    let measured = size(heading.environment(\.dynamicTypeSize, textSize), width: width)
                    XCTAssertLessThanOrEqual(measured.width, width + 0.5)
                    XCTAssertGreaterThanOrEqual(measured.height, 44)
                }
            }
        }
    }

    func testDescriptorsOnlyUseSpaceWhenExpanded() {
        let words = (1...100).map { "descriptor \($0)" }
        for width in [CGFloat(264), 346, 700] {
            for textSize in [DynamicTypeSize.large, .accessibility3] {
                let baseline = size(AlbumDescriptors(descriptors: ["calm"], isExpanded: .constant(false))
                    .environment(\.dynamicTypeSize, textSize), width: width)
                for count in [23, 100] {
                    let closed = size(AlbumDescriptors(descriptors: Array(words.prefix(count)), isExpanded: .constant(false))
                        .environment(\.dynamicTypeSize, textSize), width: width)
                    let opened = size(AlbumDescriptors(descriptors: Array(words.prefix(count)), isExpanded: .constant(true))
                        .environment(\.dynamicTypeSize, textSize), width: width)
                    XCTAssertEqual(closed.height, baseline.height, accuracy: 0.5, "count=\(count), width=\(width), text=\(textSize)")
                    XCTAssertGreaterThanOrEqual(closed.height, 44)
                    XCTAssertLessThanOrEqual(closed.width, width + 0.5)
                    XCTAssertGreaterThan(opened.height, closed.height + 20)
                    XCTAssertLessThanOrEqual(opened.width, width + 0.5)
                }
            }
        }
        let empty = size(AlbumDescriptors(descriptors: ["", " \n"], isExpanded: .constant(false)), width: 346)
        XCTAssertEqual(empty.height, 0, accuracy: 0.5)
    }

    func testUpToThreeArtistsCanWrapWithoutTruncation() {
        let credits = PlaybackCredits(track: Track(id: "three", title: "", artists: (1...3).map {
            ArtistCredit(name: "An intentionally long artist name \($0)")
        }))
        let measured = size(PlaybackCreditsButton(credits: credits) {}, width: 264)
        XCTAssertGreaterThan(measured.height, 44)
        XCTAssertLessThanOrEqual(measured.width, 264.5)
    }

    func testRatingLineFitsNarrowAndAccessibilityWidths() {
        let rating = RymRating(rating: 4.13, votes: 123456, rank: "#1,584 for 1993, #12,000 overall")
        for width in [CGFloat(264), 346, 700] {
            for textSize in [DynamicTypeSize.large, .accessibility3] {
                let measured = size(AlbumRatingLine(rym: rating, rating: 4.13, centered: true)
                    .environment(\.dynamicTypeSize, textSize), width: width)
                XCTAssertLessThanOrEqual(measured.width, width + 0.5)
                XCTAssertGreaterThan(measured.height, 0)
            }
        }
    }

    func testMiniPlayerMetadataGrowsWithAccessibleTextWithoutWrapping() {
        for width in [CGFloat(160), 320, 700] {
            let regular = size(MiniPlayerMetadata(title: "Short", artists: "Solo")
                .environment(\.dynamicTypeSize, .large), width: width)
            let accessible = size(MiniPlayerMetadata(title: "Short", artists: "Solo")
                .environment(\.dynamicTypeSize, .accessibility5), width: width)
            let long = size(MiniPlayerMetadata(title: String(repeating: "Long title ", count: 12),
                                               artists: String(repeating: "Artist · ", count: 8))
                .environment(\.dynamicTypeSize, .accessibility5), width: width)
            XCTAssertGreaterThan(accessible.height, regular.height)
            XCTAssertGreaterThan(accessible.height, 44, "the compact system accessory cannot fit this text pair")
            XCTAssertEqual(long.height, accessible.height, accuracy: 0.5)
            XCTAssertLessThanOrEqual(long.width, width + 0.5)
        }
    }

    func testQueueRowsDoNotGrowWhenEditingNarrowsTheContent() {
        let track = Track(id: "long", title: String(repeating: "A long song title ", count: 12),
                          artist: String(repeating: "Ensemble and Guest Artist ", count: 12))
        for textSize in [DynamicTypeSize.large, .accessibility3, .accessibility5] {
            for width in [CGFloat(260), 346, 600] {
                let normal = size(QueueTrackRow(track: track).environment(\.dynamicTypeSize, textSize), width: width)
                let editing = size(QueueTrackRow(track: track).environment(\.dynamicTypeSize, textSize), width: width - 80)
                XCTAssertEqual(normal.height, editing.height, accuracy: 0.5)
                XCTAssertGreaterThanOrEqual(editing.height, 44)
                XCTAssertLessThanOrEqual(editing.width, width - 79.5)
            }
        }
    }

    func testMarkdownBlocksKeepWideCodeAndTablesInsideReaderWidth() {
        let code = "let recording = \"" + String(repeating: "long-content-", count: 30) + "\""
        let source = "# Recording notes\n\nA **bold** introduction.\n\n> Quiet room.\n\n- First take\n- Final take\n\n```swift\n" + code
            + "\n```\n\n| Track | Duration |\n| --- | ---: |\n| First light | 3:42 |"
        let document = MarkdownDocument.parse(source)
        for width in [CGFloat(264), 600] {
            for textSize in [DynamicTypeSize.large, .accessibility3] {
                let measured = size(MarkdownContent(document: document).environment(\.dynamicTypeSize, textSize), width: width)
                XCTAssertLessThanOrEqual(measured.width, width + 0.5, "only individual code and table blocks may scroll horizontally")
                XCTAssertGreaterThan(measured.height, 0)
                XCTAssertTrue(measured.height.isFinite)
            }
        }
    }

    func testCountsUseTheSingularForOne() {
        XCTAssertEqual(L10n.count("count.tracks", 1), L10n.text("mobile.oneTrack"))
        XCTAssertEqual(L10n.count("count.albums", 1), L10n.text("mobile.oneAlbum"))
        XCTAssertEqual(L10n.count("count.tracks", 3), L10n.text("count.tracks", "3"))
        XCTAssertFalse(L10n.count("count.tracks", 1).contains("{0}"))
        if L10n.language == "en" {
            XCTAssertEqual(L10n.count("count.tracks", 1), "1 track")
            XCTAssertEqual(L10n.count("count.tracks", 2), "2 tracks")
        }
    }
}
