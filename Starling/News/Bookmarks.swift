import Foundation
import Observation

/// "Keep": saved stories, persisted with the article so they survive feed refreshes and offline.
@Observable @MainActor
final class Bookmarks {
    private(set) var saved: [Article] = []
    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("bookmarks.json")

    init() {
        if let data = try? Data(contentsOf: url) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            saved = (try? dec.decode([Article].self, from: data)) ?? []
        }
    }
    func contains(_ a: Article) -> Bool { saved.contains { $0.id == a.id } }
    func toggle(_ a: Article) {
        if let i = saved.firstIndex(where: { $0.id == a.id }) { saved.remove(at: i) } else { saved.insert(a, at: 0) }
        persist()
    }
    func remove(_ a: Article) { saved.removeAll { $0.id == a.id }; persist() }
    private func persist() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(saved) { try? data.write(to: url) }
    }
}
