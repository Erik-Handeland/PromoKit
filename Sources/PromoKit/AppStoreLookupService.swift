import Foundation

struct AppStoreAppInfo: Equatable {
    let appStoreID: String
    let appName: String
    let bundleID: String
    let appStoreURL: URL
    let iconURL: URL?
}

extension AppStoreAppInfo: Identifiable {
    var id: String { appStoreID }
}

enum AppStoreLookupService {
    static func appID(from input: String) -> String? {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedInput.allSatisfy(\.isNumber) {
            return trimmedInput
        }

        guard let url = URL(string: trimmedInput) else { return nil }
        let pathComponents = url.pathComponents

        for component in pathComponents {
            guard component.hasPrefix("id") else { continue }
            let id = String(component.dropFirst(2))
            if !id.isEmpty, id.allSatisfy(\.isNumber) {
                return id
            }
        }

        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "id" })?
            .value
    }

    static func lookup(from input: String) async throws -> AppStoreAppInfo {
        guard let appID = appID(from: input) else {
            throw AppStoreLookupError.invalidURL
        }

        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "id", value: appID),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier.lowercased() ?? "us")
        ]

        guard let url = components?.url else {
            throw AppStoreLookupError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode
        else {
            throw AppStoreLookupError.requestFailed
        }

        let lookupResponse = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
        guard let result = lookupResponse.results.first,
              let appStoreURL = URL(string: result.trackViewURL)
        else {
            throw AppStoreLookupError.notFound
        }

        return AppStoreAppInfo(
            appStoreID: String(result.trackID),
            appName: result.trackName,
            bundleID: result.bundleID,
            appStoreURL: appStoreURL,
            iconURL: URL(string: result.artworkURL512 ?? result.artworkURL100)
        )
    }

    static func search(for query: String, limit: Int = 8) async throws -> [AppStoreAppInfo] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: trimmedQuery),
            URLQueryItem(name: "media", value: "software"),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier.lowercased() ?? "us")
        ]

        guard let url = components?.url else {
            throw AppStoreLookupError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode
        else {
            throw AppStoreLookupError.requestFailed
        }

        let searchResponse = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
        return searchResponse.results.compactMap { result in
            guard let appStoreURL = URL(string: result.trackViewURL) else { return nil }
            return AppStoreAppInfo(
                appStoreID: String(result.trackID),
                appName: result.trackName,
                bundleID: result.bundleID,
                appStoreURL: appStoreURL,
                iconURL: URL(string: result.artworkURL512 ?? result.artworkURL100)
            )
        }
    }
}

enum AppStoreLookupError: LocalizedError {
    case invalidURL
    case requestFailed
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter an App Store URL or app ID."
        case .requestFailed:
            "The App Store lookup request failed."
        case .notFound:
            "No App Store app was found for that URL."
        }
    }
}

private struct AppStoreLookupResponse: Decodable {
    let results: [AppStoreLookupResult]
}

private struct AppStoreLookupResult: Decodable {
    let trackID: Int
    let trackName: String
    let bundleID: String
    let trackViewURL: String
    let artworkURL100: String
    let artworkURL512: String?

    private enum CodingKeys: String, CodingKey {
        case trackID = "trackId"
        case trackName
        case bundleID = "bundleId"
        case trackViewURL = "trackViewUrl"
        case artworkURL100 = "artworkUrl100"
        case artworkURL512 = "artworkUrl512"
    }
}
