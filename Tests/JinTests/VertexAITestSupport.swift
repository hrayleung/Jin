import Foundation
import XCTest
@testable import Jin

let vertexAITestPrivateKey = """
-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDA1fuTdbcrqnqP
4ut6qccSZozQT/WeeERtbQz+aDqAdR9LEDsfpO/y6Wp7m3VTmUSVPZKxHAMqmjai
8zB70uwhIUMTwVd2IvDGvw1wilMEPpyycD7qJyxCX7Mi0wRHk0Sddak8KlUWxAdu
1l9+c5IQfyH0xGFU6T45meK+6RbgVEohYrzbu9BcYOVO6tQFLRahoLjLq6VD5Z/G
55EKZvuGvj0vbXiLE6dPqcy81IGwLb79UJuKrmw6FmaCiVKvRGE6C86GtmZ5Fart
da5YTxrqi0kXEo+fy66FLAhqceRw11rVJBWnoUsDGk3/nCUr9qDsLYDZPVvEXElI
V2Eo2wExAgMBAAECggEAOnqKBQF9T2ovKeRsefHzs3JTALdG6sxZIAAioSI1n5Al
McvVyjZoJ/e+OYb+8R+5SzL1ge1XTnue1xK94McpobBnGZ4X6nUVJIh6yGbCXzan
qXtdsP+5LdW8yvJISXZxJ/kvHdZOoI1JHcU4B25/3K3ZO9O0Gp5zJt+ygifIrrWK
VFQ6S86gbaN2I5jX1By16AxTfjHxdYZyNu3D2kwJ/LS5VKkdkN33gDHymd0xTGwB
rb0r9AtkLXNtbLWg9PznuvhvfbAFkJ51oIj4NAcbbl98lDXq0jnQrP6zoTS9JsrH
Mv8/Mykv+x02VxFvnBrkHJ1B3ETbdEPbsSvt6Z3n4wKBgQDfo35EEo9ns2FbVJtf
rYRKtv/y00YoSFRfg+yYvRzCNGtKffdn6vxMVbDUBGiv9RX+cqV/NcMEoSPwhav/
aOhrxdT6mnX9ghAfT/E58DqSU9aslOkehHaIbKIOUbddkTEK9dp23RZT54REj7CJ
0F1GJdYvvjKuh4oP6MyG8g1XqwKBgQDcvW0pWxNaQy066hzq4PmUEyXqW72anY0r
0J/nwXUCpvYSAgtZztkkhvDkN29q1//3ZDo9bRybSKczJ2CFVAcNUTpLE0sQzoYm
nED7W+kHch5bbO8wGGt3UyX39aY9yzpe63/R/LpdaOuKVqUEhC+/kthgaGAZd5em
K7VYXKL+kwKBgAXi6sbl6ipjmVNrFa/eBFZnHLOKhhU3WiktcsPObnxaHtzWFfYB
RGTJ+J6MAylmfQ62e86uXpS3nReOnSla3ItBqMpz2Fk03DHGy+WnghMp68OdI8mu
2OPcYCOaWQY4dR8Bu59XUGgi9uNLGO13s4zOICYfjnvzi1nB2ehPZLSDAoGACBZE
hoxYpCjr4kmrb4t4eU1OSUy9IIn/HwjQouv6fnNhdn1urwad+/GZp7LEOTTaotSg
MZnqv2GlBoG9zoSqkXlVWmTFjkMStR1qYAsY+XXb2Nuf07JBVajNLk1onsDwTYPx
Nd89cKikYHgWKZkyKqGVncqVIrm365WUWj1il1MCgYA5J/ojhWKVy/oofiKVetRT
qZSGkyO7SKEHrzkWdBt+iOfEfgEmhpgRETOlmSlZgEXylZnTBvcnf1aNi/j0vFPy
nlqJDs/DMg+uR+/h9jfYW3wlY3tvOj77l4en7J++w2tjlUF4CKRW53/CEa0u+pGi
0qcpM7QV+HhjwJ5lS/GKYw==
-----END PRIVATE KEY-----
"""

final class VertexAITestURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeVertexAITestSessionConfiguration() -> (URLSessionConfiguration, VertexAITestURLProtocol.Type) {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [VertexAITestURLProtocol.self]
    return (config, VertexAITestURLProtocol.self)
}

func vertexAIRequestBodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else { return nil }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 16 * 1024
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
        if read < 0 {
            return nil
        }
        if read == 0 {
            break
        }
        data.append(buffer, count: read)
    }

    return data
}

func makeVertexProviderConfig(models: [ModelInfo] = []) -> ProviderConfig {
    ProviderConfig(
        id: "vertex",
        name: "Vertex AI",
        type: .vertexai,
        apiKey: "ignored",
        models: models
    )
}

func makeVertexCredentials(location: String = "global") -> ServiceAccountCredentials {
    ServiceAccountCredentials(
        type: "service_account",
        projectID: "project",
        privateKeyID: "key-id",
        privateKey: vertexAITestPrivateKey,
        clientEmail: "svc@example.com",
        clientID: "1234567890",
        authURI: "https://accounts.google.com/o/oauth2/auth",
        tokenURI: "https://oauth2.googleapis.com/token",
        authProviderX509CertURL: "https://www.googleapis.com/oauth2/v1/certs",
        clientX509CertURL: "https://www.googleapis.com/robot/v1/metadata/x509/svc%40example.com",
        location: location
    )
}
