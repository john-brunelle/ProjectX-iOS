import Foundation

struct LoginRequest: Codable {
    let userName: String
    let apiKey: String
}

struct LoginResponse: Codable {
    let token: String?
    let success: Bool
    let errorCode: Int
    let errorMessage: String?
}

struct ValidateResponse: Codable {
    let success: Bool
    let errorCode: Int
    let errorMessage: String?
    let newToken: String?
}

struct Account: Codable, Identifiable {
    let id: Int
    let name: String
    let balance: Double
    let canTrade: Bool
    let isVisible: Bool
}

struct AccountSearchRequest: Codable {
    let onlyActiveAccounts: Bool
}

struct AccountSearchResponse: Codable {
    let accounts: [Account]?
    let success: Bool
    let errorCode: Int
    let errorMessage: String?
}
