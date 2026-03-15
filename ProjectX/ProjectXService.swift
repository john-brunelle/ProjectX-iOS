import Foundation

@MainActor
class ProjectXService: ObservableObject {

    static let shared = ProjectXService()

    private let baseURL = "https://api.thefuturesdesk.projectx.com"

    private let kUsername = "px_username"
    private let kApiKey   = "px_apikey"
    private let kToken    = "px_token"

    @Published var isAuthenticated = false
    @Published var accounts: [Account] = []
    @Published var errorMessage: String?

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
        errorMessage = nil
    }

    private func post<B: Encodable, R: Decodable>(path: String, body: B, token: String?) async -> R? {
        guard let url = URL(string: baseURL + path) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/plain",       forHTTPHeaderField: "accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(R.self, from: data)
        } catch {
            print("ProjectXService error: \(error)")
            return nil
        }
    }
}

private struct EmptyBody: Encodable {}
