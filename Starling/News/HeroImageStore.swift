import UIKit
import Observation

/// Downloads and caches feed images so live (non-snapshot) articles get a hero too.
@Observable @MainActor
final class HeroImageStore {
    private(set) var images: [URL: UIImage] = [:]
    private var inflight: Set<URL> = []

    func image(for url: URL?) -> UIImage? { url.flatMap { images[$0] } }

    func load(_ url: URL?) {
        guard let url, images[url] == nil, !inflight.contains(url) else { return }
        inflight.insert(url)
        Task {
            defer { inflight.remove(url) }
            guard let (data, _) = try? await URLSession.shared.data(from: url), let img = UIImage(data: data) else { return }
            images[url] = img
        }
    }
}
