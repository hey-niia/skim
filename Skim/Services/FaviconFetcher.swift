import Foundation

enum FaviconFetcher {
    static func fetch(for urlString: String) async -> Data? {
        guard let host = URL(string: urlString)?.host else { return nil }
        guard let endpoint = URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(host)") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else { return nil }
            return data
        } catch {
            return nil
        }
    }
}
