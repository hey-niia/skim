import Foundation

struct Headline: Identifiable, Hashable {
    var id: String { urlString }
    let title: String
    let urlString: String
    let imageURLString: String?

    var url: URL? { URL(string: urlString) }
}

struct ArticleDigest: Codable, Equatable {
    let mainIdea: String
    let keyPoints: [String]
    let imageURLString: String?
}
