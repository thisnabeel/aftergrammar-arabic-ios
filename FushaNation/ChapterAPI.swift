import Foundation

enum ChapterAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Unexpected server response."
        case .httpStatus(let code):
            return "Request failed (\(code))."
        case .decoding(let err):
            return "Could not read data: \(err.localizedDescription)"
        }
    }
}

enum ChapterAPI {
    private static var jsonDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private static func debugLogDecodingFailure(endpoint: String, data: Data, error: Error) {
        #if DEBUG
        let preview = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        print("⚠️ Decoding failed for \(endpoint): \(error)")
        print("Response preview:", preview.prefix(4000))
        #endif
    }

    static func fetchChapterTree(languageID: Int = APIConfiguration.readerLanguageID) async throws -> [ChapterNode] {
        let url = URL(string: "/languages/\(languageID)/chapters", relativeTo: APIConfiguration.baseURL)!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChapterAPIError.invalidResponse }
        guard (200 ... 299).contains(http.statusCode) else { throw ChapterAPIError.httpStatus(http.statusCode) }
        do {
            let decoded = try jsonDecoder.decode(ChaptersTreeResponse.self, from: data)
            return decoded.chapters.sorted { $0.position < $1.position }
        } catch {
            throw ChapterAPIError.decoding(error)
        }
    }

    static func fetchChapterDetail(id: Int, itemsPerPage: Int? = nil, itemsPage: Int? = nil) async throws -> ChapterDetailResponse {
        var components = URLComponents(
            url: URL(string: "/chapters/\(id)", relativeTo: APIConfiguration.baseURL)!,
            resolvingAgainstBaseURL: true
        )!
        var query: [URLQueryItem] = []
        if let itemsPerPage {
            query.append(URLQueryItem(name: "items_per_page", value: String(itemsPerPage)))
        }
        if let itemsPage {
            query.append(URLQueryItem(name: "items_page", value: String(itemsPage)))
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        let url = components.url!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChapterAPIError.invalidResponse }
        guard (200 ... 299).contains(http.statusCode) else { throw ChapterAPIError.httpStatus(http.statusCode) }
        do {
            return try jsonDecoder.decode(ChapterDetailResponse.self, from: data)
        } catch {
            throw ChapterAPIError.decoding(error)
        }
    }

    static func fetchLayerQuizzes(chapterLayerId: Int) async throws -> [LayerQuiz] {
        let url = URL(string: "/chapter_layers/\(chapterLayerId)/layer_quizzes", relativeTo: APIConfiguration.baseURL)!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChapterAPIError.invalidResponse }
        guard (200 ... 299).contains(http.statusCode) else { throw ChapterAPIError.httpStatus(http.statusCode) }
        do {
            // API returns `{ "layer_quizzes": [...] }` (not a top-level array).
            struct LayerQuizzesResponse: Decodable { let layerQuizzes: [LayerQuiz] }
            if let wrapped = try? jsonDecoder.decode(LayerQuizzesResponse.self, from: data) {
                return wrapped.layerQuizzes
            }
            // Fallback in case the server ever returns a top-level array.
            return try jsonDecoder.decode([LayerQuiz].self, from: data)
        } catch {
            debugLogDecodingFailure(endpoint: "/chapter_layers/:id/layer_quizzes", data: data, error: error)
            throw ChapterAPIError.decoding(error)
        }
    }

    static func fetchChapterImageOverlays(chapterImageId: Int) async throws -> [ChapterImageOverlayDTO] {
        let url = URL(string: "/chapter_images/\(chapterImageId)/overlays", relativeTo: APIConfiguration.baseURL)!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChapterAPIError.invalidResponse }
        guard (200 ... 299).contains(http.statusCode) else { throw ChapterAPIError.httpStatus(http.statusCode) }
        do {
            let wrapped = try jsonDecoder.decode(ChapterImageOverlaysResponse.self, from: data)
            return wrapped.overlays.sorted {
                let lp = $0.position ?? Int.max
                let rp = $1.position ?? Int.max
                if lp != rp { return lp < rp }
                return $0.id < $1.id
            }
        } catch {
            debugLogDecodingFailure(endpoint: "/chapter_images/:id/overlays", data: data, error: error)
            throw ChapterAPIError.decoding(error)
        }
    }
}
