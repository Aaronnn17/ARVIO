import Foundation
import Security

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let userId: String
    let email: String
    let expiresAt: Date
}

struct UserProfile: Codable, Equatable {
    let id: String
    let email: String?
    let addons: String?
    let defaultSubtitle: String?
    let autoPlayNext: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case addons
        case defaultSubtitle = "default_subtitle"
        case autoPlayNext = "auto_play_next"
    }
}

private struct SupabaseAuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?
    let user: SupabaseUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

private struct SupabaseUser: Decodable {
    let id: String
    let email: String?
}

private struct EmailPasswordBody: Encodable {
    let email: String
    let password: String
}

private struct RefreshBody: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct CloudDeviceAuthSession: Decodable, Equatable {
    let userCode: String
    let deviceCode: String
    let verificationURL: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case userCode = "user_code"
        case deviceCode = "device_code"
        case verificationURL = "verification_url"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userCode = try container.decode(String.self, forKey: .userCode)
        deviceCode = try container.decode(String.self, forKey: .deviceCode)
        let url = (try? container.decode(String.self, forKey: .verificationURL)) ??
            (try? container.decode(String.self, forKey: .verificationURI)) ??
            ""
        verificationURL = url.isEmpty ? "https://auth.arvio.tv/?code=\(userCode)" : url
        expiresIn = (try? container.decode(Int.self, forKey: .expiresIn)) ?? 600
        interval = (try? container.decode(Int.self, forKey: .interval)) ?? 3
    }
}

private struct CloudDeviceAuthStatus {
    let status: String
    let accessToken: String?
    let refreshToken: String?
    let email: String?
    let message: String?
}

final class KeychainStore {
    private let service = "com.arvio.ios.session"

    func save<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ArvioError.requestFailed("Unable to save secure session")
        }
    }

    func load<T: Decodable>(_ type: T.Type, account: String) -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var profile: UserProfile?
    @Published private(set) var cloudDeviceAuthSession: CloudDeviceAuthSession?
    @Published private(set) var cloudDeviceAuthMessage: String?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client = JSONClient()
    private let keychain = KeychainStore()
    private let sessionAccount = "supabase-session"

    init() {
        session = keychain.load(AuthSession.self, account: sessionAccount)
    }

    var isAuthenticated: Bool {
        session != nil
    }

    func restore() async {
        guard let existing = session else { return }
        do {
            if existing.expiresAt.timeIntervalSinceNow < 120 {
                try await refreshSession()
            }
            try await loadProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        await authenticate(path: "/auth/v1/token?grant_type=password", body: EmailPasswordBody(email: email, password: password))
    }

    func signUp(email: String, password: String) async {
        await authenticate(path: "/auth/v1/signup", body: EmailPasswordBody(email: email, password: password))
    }

    func beginCloudDeviceLink() async {
        guard AppConfig.isCloudConfigured else {
            errorMessage = "Supabase is not configured for iOS"
            return
        }
        isLoading = true
        errorMessage = nil
        cloudDeviceAuthMessage = nil
        defer { isLoading = false }

        do {
            let response = try await cloudFunctionRequest(path: "/functions/v1/tv-auth-start", body: [:])
            guard (200..<300).contains(response.statusCode) else {
                throw ArvioError.requestFailed(parseCloudFunctionError(response.data, fallback: "Failed to start cloud pairing"))
            }
            cloudDeviceAuthSession = try JSONDecoder().decode(CloudDeviceAuthSession.self, from: response.data)
            cloudDeviceAuthMessage = "Open the auth page and enter the code."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pollCloudDeviceLink() async {
        guard let deviceCode = cloudDeviceAuthSession?.deviceCode else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let body = ["device_code": deviceCode]
            var response = try await cloudFunctionRequest(path: "/functions/v1/tv-auth-status", body: body)
            if response.statusCode == 404 {
                response = try await cloudFunctionRequest(path: "/functions/v1/tv-auth-poll", body: body)
            }
            guard (200..<300).contains(response.statusCode) else {
                throw ArvioError.requestFailed(parseCloudFunctionError(response.data, fallback: "Failed to poll cloud pairing"))
            }
            let status = parseCloudDeviceStatus(response.data)
            switch status.status.lowercased() {
            case "approved":
                guard let accessToken = status.accessToken, let refreshToken = status.refreshToken else {
                    throw ArvioError.requestFailed("Cloud pairing approved without session tokens")
                }
                try persist(accessToken: accessToken, refreshToken: refreshToken, email: status.email)
                try await loadProfile()
                cloudDeviceAuthSession = nil
                cloudDeviceAuthMessage = "Cloud login linked."
            case "expired":
                cloudDeviceAuthSession = nil
                cloudDeviceAuthMessage = "Cloud pairing expired. Start again."
            case "pending":
                cloudDeviceAuthMessage = "Still waiting for approval."
            default:
                cloudDeviceAuthMessage = status.message ?? "Cloud pairing failed."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        session = nil
        profile = nil
        cloudDeviceAuthSession = nil
        cloudDeviceAuthMessage = nil
        errorMessage = nil
        keychain.delete(account: sessionAccount)
    }

    func accessToken() async throws -> String {
        guard let current = session else { throw ArvioError.notAuthenticated }
        if current.expiresAt.timeIntervalSinceNow < 120 {
            try await refreshSession()
        }
        guard let token = session?.accessToken else { throw ArvioError.notAuthenticated }
        return token
    }

    func loadProfile() async throws {
        guard let current = session else { throw ArvioError.notAuthenticated }
        let rows: [UserProfile] = try await supabaseRequest(
            "/rest/v1/profiles?id=eq.\(current.userId)&select=id,email,addons,default_subtitle,auto_play_next",
            token: current.accessToken
        )
        profile = rows.first ?? UserProfile(id: current.userId, email: current.email, addons: nil, defaultSubtitle: nil, autoPlayNext: nil)
    }

    func supabaseRequest<T: Decodable, B: Encodable>(
        _ path: String,
        method: String = "GET",
        token: String,
        prefer: String? = nil,
        body: B? = nil
    ) async throws -> T {
        guard AppConfig.isCloudConfigured else {
            throw ArvioError.missingConfiguration("Supabase")
        }
        guard let url = URL(string: AppConfig.supabaseURL + path) else {
            throw ArvioError.invalidURL(path)
        }
        var headers = [
            "apikey": AppConfig.supabaseAnonKey,
            "Authorization": "Bearer \(token)"
        ]
        if let prefer {
            headers["Prefer"] = prefer
        }
        return try await client.request(url, method: method, headers: headers, body: body)
    }

    func supabaseRequest<T: Decodable>(
        _ path: String,
        method: String = "GET",
        token: String,
        prefer: String? = nil
    ) async throws -> T {
        let body: EmptyBody? = nil
        return try await supabaseRequest(path, method: method, token: token, prefer: prefer, body: body)
    }

    private func authenticate(path: String, body: EmailPasswordBody) async {
        guard AppConfig.isCloudConfigured else {
            errorMessage = "Supabase is not configured for iOS"
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let url = URL(string: AppConfig.supabaseURL + path) else {
                throw ArvioError.invalidURL(path)
            }
            let response: SupabaseAuthResponse = try await client.request(
                url,
                method: "POST",
                headers: ["apikey": AppConfig.supabaseAnonKey],
                body: body
            )
            try persist(response: response, fallbackEmail: body.email)
            try await loadProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshSession() async throws {
        guard AppConfig.isCloudConfigured else {
            throw ArvioError.missingConfiguration("Supabase")
        }
        guard let current = session else { throw ArvioError.notAuthenticated }
        guard let url = URL(string: AppConfig.supabaseURL + "/auth/v1/token?grant_type=refresh_token") else {
            throw ArvioError.invalidURL("refresh")
        }
        let response: SupabaseAuthResponse = try await client.request(
            url,
            method: "POST",
            headers: ["apikey": AppConfig.supabaseAnonKey],
            body: RefreshBody(refreshToken: current.refreshToken)
        )
        try persist(response: response, fallbackEmail: current.email)
    }

    private func persist(response: SupabaseAuthResponse, fallbackEmail: String) throws {
        let expiresAt = response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        try persist(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            userId: response.user?.id,
            email: response.user?.email ?? decodeEmail(response.accessToken) ?? fallbackEmail,
            expiresAt: expiresAt
        )
    }

    private func persist(accessToken: String, refreshToken: String, userId explicitUserId: String? = nil, email: String?, expiresAt: Date? = nil) throws {
        guard let userId = explicitUserId ?? decodeSubject(accessToken) else {
            throw ArvioError.requestFailed("Auth response missing user")
        }
        let newSession = AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userId: userId,
            email: email ?? decodeEmail(accessToken) ?? "ARVIO",
            expiresAt: expiresAt ?? decodeExpiration(accessToken) ?? Date().addingTimeInterval(3600)
        )
        try keychain.save(newSession, account: sessionAccount)
        session = newSession
    }

    private func cloudFunctionRequest(path: String, body: [String: String]) async throws -> (data: Data, statusCode: Int) {
        guard AppConfig.isCloudConfigured else {
            throw ArvioError.missingConfiguration("Supabase")
        }
        guard let url = URL(string: AppConfig.supabaseURL + path) else {
            throw ArvioError.invalidURL(path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ArvioError.requestFailed("No HTTP response")
        }
        return (data, http.statusCode)
    }

    private func parseCloudFunctionError(_ data: Data, fallback: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)?.nilIfBlank ?? fallback
        }
        return (object["error"] as? String)?.nilIfBlank ??
            (object["message"] as? String)?.nilIfBlank ??
            (object["error_description"] as? String)?.nilIfBlank ??
            fallback
    }

    private func parseCloudDeviceStatus(_ data: Data) -> CloudDeviceAuthStatus {
        let object = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return CloudDeviceAuthStatus(
            status: (object["status"] as? String) ?? "error",
            accessToken: (object["access_token"] as? String)?.nilIfBlank,
            refreshToken: (object["refresh_token"] as? String)?.nilIfBlank,
            email: (object["email"] as? String)?.nilIfBlank,
            message: (object["message"] as? String)?.nilIfBlank
        )
    }

    private func decodeSubject(_ jwt: String) -> String? {
        decodePayload(jwt)?["sub"] as? String
    }

    private func decodeEmail(_ jwt: String) -> String? {
        decodePayload(jwt)?["email"] as? String
    }

    private func decodeExpiration(_ jwt: String) -> Date? {
        guard let raw = decodePayload(jwt)?["exp"] else { return nil }
        let seconds: TimeInterval?
        if let value = raw as? Double {
            seconds = value
        } else if let value = raw as? Int {
            seconds = TimeInterval(value)
        } else if let value = raw as? String {
            seconds = TimeInterval(value)
        } else {
            seconds = nil
        }
        return seconds.map { Date(timeIntervalSince1970: $0) }
    }

    private func decodePayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
