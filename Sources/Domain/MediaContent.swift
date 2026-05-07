import Foundation

enum MediaAssetDisposition: String, Codable, Equatable, Sendable {
    case managed
    case externalReference
}

private func inferredMediaAssetDisposition(data: Data?, url: URL?) -> MediaAssetDisposition {
    if data != nil || url?.isFileURL == true {
        return .managed
    }
    if url != nil {
        return .externalReference
    }
    return .managed
}

/// Image content with in-memory data, a local attachment URL, or an external remote URL.
struct ImageContent: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case mimeType
        case data
        case url
        case assetDisposition
    }

    let mimeType: String // image/jpeg, image/png, image/webp
    let data: Data?
    let url: URL?
    let assetDisposition: MediaAssetDisposition

    var remoteURL: URL? {
        guard let url, !url.isFileURL else { return nil }
        return url
    }

    init(
        mimeType: String,
        data: Data? = nil,
        url: URL? = nil,
        assetDisposition: MediaAssetDisposition? = nil
    ) {
        self.mimeType = mimeType
        self.data = data
        self.url = url
        self.assetDisposition = assetDisposition ?? inferredMediaAssetDisposition(data: data, url: url)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mimeType = try container.decode(String.self, forKey: .mimeType)
        let data = try container.decodeIfPresent(Data.self, forKey: .data)
        let url = try container.decodeIfPresent(URL.self, forKey: .url)
        let assetDisposition = try container.decodeIfPresent(MediaAssetDisposition.self, forKey: .assetDisposition)

        self.init(mimeType: mimeType, data: data, url: url, assetDisposition: assetDisposition)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(assetDisposition, forKey: .assetDisposition)
    }
}

/// Video content with in-memory data, a local attachment URL, or an external remote URL.
struct VideoContent: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case mimeType
        case data
        case url
        case assetDisposition
    }

    let mimeType: String // video/mp4, video/webm
    let data: Data?
    let url: URL?
    let assetDisposition: MediaAssetDisposition

    var remoteURL: URL? {
        guard let url, !url.isFileURL else { return nil }
        return url
    }

    init(
        mimeType: String,
        data: Data? = nil,
        url: URL? = nil,
        assetDisposition: MediaAssetDisposition? = nil
    ) {
        self.mimeType = mimeType
        self.data = data
        self.url = url
        self.assetDisposition = assetDisposition ?? inferredMediaAssetDisposition(data: data, url: url)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mimeType = try container.decode(String.self, forKey: .mimeType)
        let data = try container.decodeIfPresent(Data.self, forKey: .data)
        let url = try container.decodeIfPresent(URL.self, forKey: .url)
        let assetDisposition = try container.decodeIfPresent(MediaAssetDisposition.self, forKey: .assetDisposition)

        self.init(mimeType: mimeType, data: data, url: url, assetDisposition: assetDisposition)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(assetDisposition, forKey: .assetDisposition)
    }
}

/// File content (PDFs, documents)
struct FileContent: Codable, Sendable {
    let mimeType: String
    let filename: String
    let data: Data?
    let url: URL?
    let extractedText: String?

    init(
        mimeType: String,
        filename: String,
        data: Data? = nil,
        url: URL? = nil,
        extractedText: String? = nil
    ) {
        self.mimeType = mimeType
        self.filename = filename
        self.data = data
        self.url = url
        self.extractedText = extractedText
    }
}

/// Audio content (OpenAI only)
struct AudioContent: Codable, Sendable {
    let mimeType: String // audio/mp3, audio/wav
    let data: Data?
    let url: URL?

    init(mimeType: String, data: Data? = nil, url: URL? = nil) {
        self.mimeType = mimeType
        self.data = data
        self.url = url
    }
}
