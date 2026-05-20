import AppKit
import SwiftUI

/// Tiny in-memory image cache shared by the library, banners, and menu bar so
/// scrolling and animations don't refetch the same Steam artwork repeatedly.
/// Backed by `NSCache` so it cooperates with system memory pressure.
@MainActor
final class RemoteImageCache: ObservableObject {
    static let shared = RemoteImageCache()

    private let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 256
        return c
    }()
    /// Inflight loads keyed by URL; we hold Data tasks (Sendable) and decode `NSImage`
    /// on the main actor to stay clean on macOS 13 where `NSImage: Sendable` is not
    /// available.
    private var inflight: [URL: Task<Data?, Never>] = [:]

    func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        return cache.object(forKey: url as NSURL)
    }

    @discardableResult
    func load(_ url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        let task: Task<Data?, Never>
        if let existing = inflight[url] {
            task = existing
        } else {
            task = Task<Data?, Never> {
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        return nil
                    }
                    return data
                } catch {
                    return nil
                }
            }
            inflight[url] = task
        }
        defer { inflight[url] = nil }
        guard let data = await task.value, let image = NSImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    func clear() {
        for task in inflight.values {
            task.cancel()
        }
        inflight.removeAll()
        cache.removeAllObjects()
    }

    func prefetch(_ urls: [URL]) async {
        if urls.isEmpty { return }
        var seen = Set<URL>()
        for url in urls {
            if Task.isCancelled { return }
            if seen.insert(url).inserted {
                _ = await load(url)
            }
        }
    }
}

/// Drop-in replacement for `AsyncImage` that consults `RemoteImageCache`. Identifying
/// the view by URL keeps SwiftUI from re-issuing the fetch when the parent re-renders.
struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL?
    let contentMode: ContentMode
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: NSImage?

    init(url: URL?,
         contentMode: ContentMode = .fill,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let cached = RemoteImageCache.shared.image(for: url) {
                image = cached
                return
            }
            image = await RemoteImageCache.shared.load(url)
        }
    }
}
