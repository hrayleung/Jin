import Foundation
import Security

actor VertexAIAccessTokenProvider {
    private let serviceAccountJSON: ServiceAccountCredentials
    private let networkManager: NetworkManager
    private var cachedToken: (token: String, expiresAt: Date)?

    init(
        serviceAccountJSON: ServiceAccountCredentials,
        networkManager: NetworkManager
    ) {
        self.serviceAccountJSON = serviceAccountJSON
        self.networkManager = networkManager
    }

    func accessToken() async throws -> String {
        if let cachedToken, cachedToken.expiresAt > Date().addingTimeInterval(60) {
            return cachedToken.token
        }

        let jwt = try createJWT()
        let token = try await exchangeJWTForToken(jwt)
        cachedToken = (
            token: token.accessToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn))
        )
        return token.accessToken
    }

    private func createJWT() throws -> String {
        let header = JWTHeader(alg: "RS256", typ: "JWT")
        let now = Date()
        let claims = JWTClaims(
            iss: serviceAccountJSON.clientEmail,
            scope: "https://www.googleapis.com/auth/cloud-platform",
            aud: serviceAccountJSON.tokenURI,
            iat: Int(now.timeIntervalSince1970),
            exp: Int(now.addingTimeInterval(3600).timeIntervalSince1970)
        )

        let headerData = try JSONEncoder().encode(header)
        let claimsData = try JSONEncoder().encode(claims)
        let headerBase64 = headerData.base64URLEncodedString()
        let claimsBase64 = claimsData.base64URLEncodedString()
        let message = "\(headerBase64).\(claimsBase64)"
        let signature = try signWithPrivateKey(message: message, privateKey: serviceAccountJSON.privateKey)
        return "\(message).\(signature)"
    }

    private func signWithPrivateKey(message: String, privateKey: String) throws -> String {
        let key = try loadRSAPrivateKey(pem: privateKey)
        let messageData = Data(message.utf8)
        let algorithm = SecKeyAlgorithm.rsaSignatureMessagePKCS1v15SHA256

        guard SecKeyIsAlgorithmSupported(key, .sign, algorithm) else {
            throw LLMError.invalidRequest(message: "RSA signing algorithm not supported")
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, algorithm, messageData as CFData, &error) as Data? else {
            let description = error?.takeRetainedValue().localizedDescription ?? "Unknown signing error"
            throw LLMError.invalidRequest(message: "Failed to sign JWT: \(description)")
        }

        return signature.base64URLEncodedString()
    }

    private func loadRSAPrivateKey(pem: String) throws -> SecKey {
        let pemBlock = try PEMBlock.parse(pem: pem)
        let pkcs1DER = try extractPKCS1DER(from: pemBlock)
        let keySizeInBits = try RSAKeyParsing.modulusSizeInBits(fromPKCS1RSAPrivateKey: pkcs1DER)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: keySizeInBits
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1DER as CFData, attributes as CFDictionary, &error) else {
            let description = error?.takeRetainedValue().localizedDescription ?? "Unknown key error"
            throw LLMError.invalidRequest(message: "Failed to load RSA private key: \(description)")
        }
        return key
    }

    private func extractPKCS1DER(from pemBlock: PEMBlock) throws -> Data {
        switch pemBlock.label {
        case "RSA PRIVATE KEY":
            return pemBlock.derBytes
        case "PRIVATE KEY":
            return try PKCS8.extractPKCS1RSAPrivateKey(from: pemBlock.derBytes)
        default:
            if let extracted = try? PKCS8.extractPKCS1RSAPrivateKey(from: pemBlock.derBytes) {
                return extracted
            }
            return pemBlock.derBytes
        }
    }

    private func exchangeJWTForToken(_ jwt: String) async throws -> TokenResponse {
        let body = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(jwt)"
        let request = NetworkRequestFactory.makeRequest(
            url: try validatedURL(serviceAccountJSON.tokenURI),
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body.data(using: .utf8)
        )

        let (data, _) = try await networkManager.sendRequest(request)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}
