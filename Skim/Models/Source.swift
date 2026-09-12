import Foundation

struct Source: Identifiable, Codable, Equatable {
    let id: UUID
    var urlString: String
    var title: String
    var faviconData: Data?
    var addedAt: Date

    init(id: UUID = UUID(), urlString: String, title: String, faviconData: Data? = nil, addedAt: Date = Date()) {
        self.id = id
        self.urlString = urlString
        self.title = title
        self.faviconData = faviconData
        self.addedAt = addedAt
    }

    var url: URL? {
        URL(string: urlString)
    }

    var host: String {
        url?.host?.replacingOccurrences(of: "www.", with: "") ?? urlString
    }

    var initial: String {
        String(title.first ?? host.first ?? "?").uppercased()
    }
}
