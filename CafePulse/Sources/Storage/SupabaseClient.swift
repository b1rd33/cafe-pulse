import Foundation

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case notAuthenticated
    case httpError(statusCode: Int, body: String)
    case invalidCallbackURL
    case tokenRefreshFailed(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Not authenticated — sign in first."
        case .httpError(let code, let body):
            "HTTP \(code): \(body)"
        case .invalidCallbackURL:
            "Invalid auth callback URL."
        case .tokenRefreshFailed(let reason):
            "Token refresh failed: \(reason)"
        case .networkError(let error):
            "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - SupabaseClient

final class SupabaseClient: Sendable {

    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(
        url: URL = SupabaseConfig.url,
        publishableKey: String = SupabaseConfig.publishableKey,
        session: URLSession = .shared
    ) {
        self.baseURL = url
        self.apiKey = publishableKey
        self.session = session
    }

    // MARK: - Auth State

    var isAuthenticated: Bool {
        KeychainHelper.loadString(key: KeychainHelper.accessTokenKey) != nil
    }

    var currentAccessToken: String? {
        KeychainHelper.loadString(key: KeychainHelper.accessTokenKey)
    }

    // MARK: - Auth: Magic Link

    func sendMagicLink(email: String) async throws {
        let url = baseURL.appendingPathComponent("auth/v1/otp")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": email,
            "create_user": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // GoTrue uses the redirectTo header for OTP magic links
        request.addValue(SupabaseConfig.callbackURL, forHTTPHeaderField: "redirect_to")

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SupabaseError.httpError(
                statusCode: code,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    // MARK: - Auth: Callback

    /// Parse the URL fragment from the magic link redirect.
    /// Expected format: cafepulse://auth/callback#access_token=...&refresh_token=...&expires_in=...
    func handleCallback(url: URL) -> Bool {
        guard let fragment = url.fragment else { return false }

        var params: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            params[String(kv[0])] = String(kv[1])
        }

        guard let accessToken = params["access_token"],
              let refreshToken = params["refresh_token"],
              let expiresInString = params["expires_in"],
              let expiresIn = TimeInterval(expiresInString)
        else {
            return false
        }

        let expiry = Date.now.addingTimeInterval(expiresIn)

        let saved = KeychainHelper.save(key: KeychainHelper.accessTokenKey, string: accessToken)
            && KeychainHelper.save(key: KeychainHelper.refreshTokenKey, string: refreshToken)
            && KeychainHelper.saveDate(key: KeychainHelper.tokenExpiryKey, date: expiry)

        return saved
    }

    // MARK: - Auth: Token Refresh

    func refreshTokenIfNeeded() async throws {
        guard let expiry = KeychainHelper.loadDate(key: KeychainHelper.tokenExpiryKey) else {
            // No expiry stored — if we have a token, try to use it; otherwise bail
            guard isAuthenticated else { throw SupabaseError.notAuthenticated }
            return
        }

        // Refresh if expired or within 60 seconds of expiry
        guard expiry.timeIntervalSinceNow < 60 else { return }

        guard let refreshToken = KeychainHelper.loadString(key: KeychainHelper.refreshTokenKey) else {
            throw SupabaseError.tokenRefreshFailed("No refresh token in Keychain.")
        }

        let url = baseURL.appendingPathComponent("auth/v1/token")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["refresh_token": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await perform(request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseError.tokenRefreshFailed("HTTP \(code): \(body)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccess = json["access_token"] as? String,
              let newRefresh = json["refresh_token"] as? String,
              let newExpiresIn = json["expires_in"] as? TimeInterval
        else {
            throw SupabaseError.tokenRefreshFailed("Unexpected response format.")
        }

        let newExpiry = Date.now.addingTimeInterval(newExpiresIn)
        _ = KeychainHelper.save(key: KeychainHelper.accessTokenKey, string: newAccess)
        _ = KeychainHelper.save(key: KeychainHelper.refreshTokenKey, string: newRefresh)
        _ = KeychainHelper.saveDate(key: KeychainHelper.tokenExpiryKey, date: newExpiry)
    }

    // MARK: - Auth: Sign Out

    func signOut() {
        KeychainHelper.deleteAll()
    }

    // MARK: - CRUD: Sessions

    func upsertSession(_ session: Session) async throws {
        try await refreshTokenIfNeeded()

        let payload = SessionPayload(
            id: session.id,
            cafeName: session.cafeName,
            location: session.location,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            tags: session.tags
        )

        let url = baseURL.appendingPathComponent("rest/v1/sessions")
        var request = authenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(payload)

        try await performCRUD(request)
    }

    // MARK: - CRUD: Audio Samples

    func upsertAudioSamples(_ samples: [AudioSample]) async throws {
        guard !samples.isEmpty else { return }
        try await refreshTokenIfNeeded()

        let payloads = samples.map { s in
            AudioSamplePayload(
                id: s.id,
                sessionId: s.sessionId,
                timestamp: s.timestamp,
                overallDb: s.overallDB,
                musicBandDb: s.musicBandDB,
                voiceBandDb: s.voiceBandDB,
                peakDb: s.peakDB,
                spectralFlatness: s.spectralFlatness,
                selfTalkDetected: s.selfTalkDetected,
                voiceBandVariance: s.voiceBandVariance
            )
        }

        let url = baseURL.appendingPathComponent("rest/v1/audio_samples")
        var request = authenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(payloads)

        try await performCRUD(request)
    }

    // MARK: - CRUD: Crowd Estimates

    func upsertCrowdEstimates(_ estimates: [CrowdEstimate]) async throws {
        guard !estimates.isEmpty else { return }
        try await refreshTokenIfNeeded()

        let payloads = estimates.map { e in
            CrowdEstimatePayload(
                id: e.id,
                sessionId: e.sessionId,
                timestamp: e.timestamp,
                fullness: e.fullness,
                peopleCount: e.peopleCount
            )
        }

        let url = baseURL.appendingPathComponent("rest/v1/crowd_estimates")
        var request = authenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(payloads)

        try await performCRUD(request)
    }

    // MARK: - Private Helpers

    private func authenticatedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = currentAccessToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw SupabaseError.networkError(error)
        }
    }

    private func performCRUD(_ request: URLRequest) async throws {
        let (data, response) = try await perform(request)

        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.httpError(statusCode: 0, body: "No HTTP response")
        }

        // 2xx = success, 409 = conflict on upsert (treat as success)
        guard (200..<300).contains(http.statusCode) || http.statusCode == 409 else {
            throw SupabaseError.httpError(
                statusCode: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }
}

// MARK: - Upload Payloads (exclude syncedAt and other local-only fields)

private struct SessionPayload: Codable {
    let id: UUID
    let cafeName: String
    let location: String?
    let startedAt: Date
    let endedAt: Date?
    let tags: [String]
}

private struct AudioSamplePayload: Codable {
    let id: UUID
    let sessionId: UUID
    let timestamp: Date
    let overallDb: Float
    let musicBandDb: Float
    let voiceBandDb: Float
    let peakDb: Float
    let spectralFlatness: Float
    let selfTalkDetected: Bool
    let voiceBandVariance: Float
}

private struct CrowdEstimatePayload: Codable {
    let id: UUID
    let sessionId: UUID
    let timestamp: Date
    let fullness: CrowdFullness
    let peopleCount: Int?
}
