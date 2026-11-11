import Foundation
import ImageIO
import UIKit

// Covers are looked up in memory, then in a downloaded album's pinned cover,
// then in the disk cache, and only then fetched. Cache changes retire writes;
// authorization changes also retire the responses visible to waiting views.
actor ArtworkStore {
    static let shared = ArtworkStore()
    private struct Request {
        let id: UUID
        let task: Task<UIImage?, Never>
    }
    private let images = NSCache<NSString, UIImage>()
    private var pending: [String: Request] = [:]
    private var missing: [String: Date] = [:]
    private var disk: URL?
    private var generation = UUID()
    private var requestContext = UUID()
    #if DEBUG
    private(set) var coalescedRequestsForTesting = 0
    #endif

    init() { images.totalCostLimit = 24 * 1024 * 1024; images.countLimit = 120 }

    func retireAuthorization() {
        // Permissions can change without changing the server or cache switch.
        // Retire responses and writers while retaining the current disk path.
        configure(disk: disk)
    }

    func configure(disk: URL?, preservingRequests: Bool = false) {
        generation = UUID()
        if !preservingRequests {
            requestContext = UUID()
            pending.values.forEach { $0.task.cancel() }
            pending.removeAll()
        }
        self.disk = disk
        images.removeAllObjects()
        missing.removeAll()
    }

    func image(url: URL, session: URLSession, pixels: Int, pinned: URL? = nil) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let token = generation
        let context = requestContext
        let key = url.absoluteString + ":\(pixels)"
        if let image = images.object(forKey: key as NSString) { return image }
        if let pinned, let data = try? Data(contentsOf: pinned), let image = Self.decode(data, pixels: pixels) {
            store(image, key: key)
            return image
        }
        let file = disk?.appendingPathComponent(digest(url.absoluteString) + ".img")
        if let file, let data = try? Data(contentsOf: file), let image = Self.decode(data, pixels: pixels) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            store(image, key: key)
            return image
        }
        if let date = missing[key], Date().timeIntervalSince(date) < 30 { return nil }
        let request: Request
        if let existing = pending[key] {
            #if DEBUG
            coalescedRequestsForTesting += 1
            #endif
            request = existing
        } else {
            let id = UUID()
            let task = Task<UIImage?, Never> {
                var downloaded: Data?
                do {
                    let (data, response) = try await session.data(from: url)
                    try APIClient.validate(response)
                    if data.count < 20 * 1024 * 1024, response.mimeType != "image/svg+xml" { downloaded = data }
                } catch {}
                // This task resumes on the artwork actor. No suspension may
                // separate the ownership check from file and cache updates.
                guard requestContext == context, pending[key]?.id == id, !Task.isCancelled else { return nil }
                pending.removeValue(forKey: key)
                guard let data = downloaded, let image = Self.decode(data, pixels: pixels) else {
                    if generation == token { missing[key] = Date() }
                    return nil
                }
                if generation == token {
                    if let file { try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
                    store(image, key: key)
                }
                // Cache switches do not change a view's image task identity.
                // Keep its response visible without refilling a retired cache.
                return image
            }
            request = Request(id: id, task: task)
            pending[key] = request
        }
        let image = await request.task.value
        // Joined callers also cross the actor suspension boundary; they must
        // not receive a retired response after a new authorization.
        guard requestContext == context, !Task.isCancelled else { return nil }
        return image
    }

    private func store(_ image: UIImage, key: String) {
        let bytes = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
        images.setObject(image, forKey: key as NSString, cost: bytes)
    }

    private static func decode(_ data: Data, pixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}
