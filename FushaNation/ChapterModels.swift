import Foundation

struct ChaptersTreeResponse: Decodable {
    let chapters: [ChapterNode]
}

struct ChapterNode: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let description: String?
    let chapterId: Int?
    let position: Int
    let languageId: Int
    /// `"Free"` or `"Premium"` from API; optional for older payloads.
    let tier: String?
    let children: [ChapterNode]

    var isPremiumTier: Bool {
        guard let t = tier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !t.isEmpty else { return false }
        return t == "premium"
    }
}

struct ChapterDetailResponse: Decodable {
    let chapter: ChapterMetadata
    let chapterImages: [ChapterImageDTO]?
    let language: LanguageInfo
    let chapterLayers: [ChapterLayer]
    let itemsLayerId: Int?
    let itemsPage: Int?
    let itemsPerPage: Int?
    let viewerIsAdmin: Bool?
}

struct ChapterMetadata: Decodable {
    let id: Int
    let title: String
    let description: String?
    let chapterMode: String?
    let tier: String?
    let chapterId: Int?
    let position: Int
    let languageId: Int

    var isPremiumTier: Bool {
        guard let t = tier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !t.isEmpty else { return false }
        return t == "premium"
    }
}

struct LanguageInfo: Decodable {
    let id: Int
    let direction: String?
}

struct ChapterLayer: Decodable, Identifiable {
    let id: Int
    let title: String
    let active: Bool
    let isDefault: Bool
    let position: Int
    let chapterLayerItemsCount: Int?
    let chapterLayerItemsHasMore: Bool?
    let chapterLayerItems: [ChapterLayerItem]
}

/// Optional reading variant for a layer item (e.g. harakaat, grammar).
struct ChapterSubLayerItem: Decodable, Identifiable, Hashable {
    let id: Int
    let languageChapterSublayerId: Int
    let sublayerName: String
    let body: String
    let hint: String?
}

struct ChapterLayerItem: Decodable, Identifiable, Hashable {
    let id: Int
    let chapterLayerId: Int
    let body: String
    let style: String
    let hint: String?
    let position: Int
    let subLayerItems: [ChapterSubLayerItem]

    private enum CodingKeys: String, CodingKey {
        case id, chapterLayerId, body, style, hint, position, subLayerItems
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        chapterLayerId = try c.decode(Int.self, forKey: .chapterLayerId)
        body = try c.decode(String.self, forKey: .body)
        style = try c.decode(String.self, forKey: .style)
        hint = try c.decodeIfPresent(String.self, forKey: .hint)
        position = try c.decode(Int.self, forKey: .position)
        subLayerItems = try c.decodeIfPresent([ChapterSubLayerItem].self, forKey: .subLayerItems) ?? []
    }

    /// Merge helper when building layers in memory (pagination).
    init(
        id: Int,
        chapterLayerId: Int,
        body: String,
        style: String,
        hint: String?,
        position: Int,
        subLayerItems: [ChapterSubLayerItem]
    ) {
        self.id = id
        self.chapterLayerId = chapterLayerId
        self.body = body
        self.style = style
        self.hint = hint
        self.position = position
        self.subLayerItems = subLayerItems
    }

    func resolvedBody(sublayerSelection: String?) -> String {
        guard let sel = sublayerSelection?.trimmingCharacters(in: .whitespacesAndNewlines), !sel.isEmpty else {
            return body
        }
        guard let match = subLayerItems.first(where: {
            $0.sublayerName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(sel) == .orderedSame
        }) else {
            return body
        }
        let trimmed = match.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? body : match.body
    }

    func resolvedHint(sublayerSelection: String?) -> String? {
        guard let sel = sublayerSelection?.trimmingCharacters(in: .whitespacesAndNewlines), !sel.isEmpty else {
            return hint
        }
        guard let match = subLayerItems.first(where: {
            $0.sublayerName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(sel) == .orderedSame
        }) else {
            return hint
        }
        if let h = match.hint?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
            return h
        }
        return hint
    }
}

// MARK: - Image chapters (read-only)

struct ChapterImageDTO: Decodable, Identifiable, Hashable {
    let id: Int
    let chapterId: Int
    let imageUrl: String
    let originalFilename: String?
    let position: Int?
}

struct ChapterImageOverlaysResponse: Decodable {
    let overlays: [ChapterImageOverlayDTO]
}

struct ChapterImageOverlayDTO: Decodable, Identifiable, Hashable {
    let id: Int
    let chapterImageId: Int
    let overlayType: String?
    let shape: [String: JSONValue]?
    let label: String?
    /// Primary API key `original`; older payloads used `original_arabic`.
    let original: String?
    let translation: String?
    let position: Int?

    private enum CodingKeys: String, CodingKey {
        case id, chapterImageId, overlayType, shape, label, translation, position
        case original
        case originalArabic = "original_arabic"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        chapterImageId = try c.decode(Int.self, forKey: .chapterImageId)
        overlayType = try c.decodeIfPresent(String.self, forKey: .overlayType)
        shape = try c.decodeIfPresent([String: JSONValue].self, forKey: .shape)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        translation = try c.decodeIfPresent(String.self, forKey: .translation)
        position = try c.decodeIfPresent(Int.self, forKey: .position)
        original = try c.decodeIfPresent(String.self, forKey: .original)
            ?? c.decodeIfPresent(String.self, forKey: .originalArabic)
    }
}

enum JSONValue: Decodable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Double.self) {
            self = .number(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([String: JSONValue].self) {
            self = .object(v)
        } else if let v = try? container.decode([JSONValue].self) {
            self = .array(v)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }
}

// MARK: - Layer quizzes

struct LayerQuiz: Decodable, Identifiable, Hashable {
    let id: Int
    let chapterLayerId: Int
    let title: String?
    let layerQuizQuestions: [LayerQuizQuestion]
}

struct LayerQuizQuestion: Decodable, Identifiable, Hashable {
    let id: Int
    let layerQuizId: Int
    let original: String?
    let english: String?
    let position: Int?
    let layerItemQuizAnswers: [LayerItemQuizAnswer]
}

struct LayerItemQuizAnswer: Decodable, Identifiable, Hashable {
    let id: Int
    let layerQuizQuestionId: Int
    let original: String?
    let english: String?
    let position: Int?
    let correct: Bool?
}
