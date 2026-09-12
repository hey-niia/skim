import Foundation
import Combine

@MainActor
final class SourceStore: ObservableObject {
    static let maxSources = 5

    @Published private(set) var sources: [Source] = []
    @Published var selectedSourceID: UUID?

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Skim", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("sources.json")
        load()
        if selectedSourceID == nil {
            selectedSourceID = sources.first?.id
        }
    }

    var canAddMore: Bool { sources.count < Self.maxSources }

    var selectedSource: Source? {
        guard let id = selectedSourceID else { return nil }
        return sources.first { $0.id == id }
    }

    func add(_ source: Source) {
        guard canAddMore else { return }
        sources.append(source)
        selectedSourceID = source.id
        save()
    }

    func remove(_ id: UUID) {
        sources.removeAll { $0.id == id }
        if selectedSourceID == id {
            selectedSourceID = sources.first?.id
        }
        save()
    }

    func updateFavicon(for id: UUID, data: Data) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].faviconData = data
        save()
    }

    func updateTitle(for id: UUID, title: String) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].title = title
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([Source].self, from: data) {
            sources = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
