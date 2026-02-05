import Foundation

struct MultipartFormDataBuilder {
    private let boundary: String
    private var body = Data()

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    mutating func addField(name: String, value: String) {
        let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(escapedName)\"\r\n\r\n")
        body.appendString(value)
        body.appendString("\r\n")
    }

    mutating func addFileField(name: String, filename: String, mimeType: String, data: Data) {
        let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedFilename = filename.replacingOccurrences(of: "\"", with: "\\\"")
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(escapedName)\"; filename=\"\(escapedFilename)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.appendString("\r\n")
    }

    func buildBody() -> Data {
        var out = body
        out.appendString("--\(boundary)--\r\n")
        return out
    }

    func contentTypeHeader() -> String {
        "multipart/form-data; boundary=\(boundary)"
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

