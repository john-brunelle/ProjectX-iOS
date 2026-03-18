import Foundation
import Observation

@MainActor
@Observable
class ProjectXService {

    static let shared = ProjectXService()

    private let baseURL = "https://api.topstepx.com"

    private let kUsername = "px_username"
    private let kApiKey   = "px_apikey"
    private let kToken    = "px_token"

    private let kActiveAccountId = "px_activeAccountId"

    var isAuthenticated = false
    var accounts: [Account] = []
    var activeAccount: Account? = nil {
        didSet {
            if let id = activeAccount?.id {
                UserDefaults.standard.set(id, forKey: kActiveAccountId)
            } else {
                UserDefaults.standard.removeObject(forKey: kActiveAccountId)
            }
        }
    }
    var errorMessage: String?

    /// Cached contract id → name mapping for display purposes.
    var contractNameCache: [String: String] = [:]

    /// Look up a display name for a contract ID. Falls back to the raw ID.
    func contractName(for contractId: String) -> String {
        contractNameCache[contractId] ?? contractId
    }

    /// Populate the cache from an array of contracts.
    func cacheContractNames(_ contracts: [Contract]) {
        for c in contracts {
            contractNameCache[c.id] = c.name
        }
    }

    var savedUsername: String? { KeychainHelper.load(for: kUsername) }
    var savedApiKey:   String? { KeychainHelper.load(for: kApiKey)   }
    var sessionToken:  String? { KeychainHelper.load(for: kToken)    }

    func login(userName: String, apiKey: String) async -> Bool {
        let body = LoginRequest(userName: userName, apiKey: apiKey)
        guard let response: LoginResponse = await post(path: "/api/Auth/loginKey", body: body, token: nil) else {
            errorMessage = "Network error during login"
            return false
        }
        guard response.success, let token = response.token else {
            errorMessage = response.errorMessage ?? "Login failed (code \(response.errorCode))"
            return false
        }
        KeychainHelper.save(userName, for: kUsername)
        KeychainHelper.save(apiKey,   for: kApiKey)
        KeychainHelper.save(token,    for: kToken)
        isAuthenticated = true
        errorMessage = nil
        return true
    }

    func validateAndRefreshToken() async -> Bool {
        guard let token = sessionToken else { return false }
        guard let response: ValidateResponse = await post(path: "/api/Auth/validate", body: EmptyBody(), token: token) else {
            return false
        }
        if response.success {
            if let newToken = response.newToken {
                KeychainHelper.save(newToken, for: kToken)
            }
            isAuthenticated = true
            return true
        }
        logout()
        return false
    }

    func logout() {
        KeychainHelper.delete(for: kToken)
        isAuthenticated = false
        accounts = []
        activeAccount = nil
    }

    func fetchAccounts(onlyActive: Bool = true) async {
        guard let token = sessionToken else { errorMessage = "Not authenticated"; return }
        let body = AccountSearchRequest(onlyActiveAccounts: onlyActive)
        guard let response: AccountSearchResponse = await post(path: "/api/Account/search", body: body, token: token) else {
            errorMessage = "Failed to fetch accounts"
            return
        }
        guard response.success else {
            errorMessage = response.errorMessage ?? "Account fetch failed (code \(response.errorCode))"
            return
        }
        accounts = response.accounts ?? []
        if activeAccount == nil {
            let savedId = UserDefaults.standard.integer(forKey: kActiveAccountId)
            activeAccount = accounts.first(where: { $0.id == savedId }) ?? accounts.first
        }
        errorMessage = nil
    }

    func post<B: Encodable, R: Decodable>(path: String, body: B, token: String?) async -> R? {
        guard let url = URL(string: baseURL + path) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/plain",       forHTTPHeaderField: "accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        // ── Rate Limiter Governor ──
        await RateLimiter.shared.acquire(bucket: RateLimiter.bucket(for: path))

        let start = Date()
        let requestBodyStr = try? String(data: JSONEncoder().encode(body), encoding: .utf8)

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, httpResponse) = try await URLSession.shared.data(for: request)
            let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode
            let duration = Date().timeIntervalSince(start)
            let responseStr = String(data: data, encoding: .utf8)

            if let statusCode {
                print("ProjectXService [\(path)] HTTP \(statusCode)")
            }
            #if DEBUG
            if let raw = responseStr {
                print("ProjectXService [\(path)] response: \(raw)")
            }
            #endif

            NetworkLogger.shared.log(NetworkLogger.Entry(
                timestamp: start, source: .rest, method: "POST", path: path,
                statusCode: statusCode, duration: duration,
                requestBody: requestBodyStr, responseBody: responseStr, error: nil
            ))

            return try JSONDecoder().decode(R.self, from: data)
        } catch {
            let duration = Date().timeIntervalSince(start)
            print("ProjectXService [\(path)] error: \(error)")

            NetworkLogger.shared.log(NetworkLogger.Entry(
                timestamp: start, source: .rest, method: "POST", path: path,
                statusCode: nil, duration: duration,
                requestBody: requestBodyStr, responseBody: nil,
                error: error.localizedDescription
            ))

            return nil
        }
    }
}

private struct EmptyBody: Encodable {}
