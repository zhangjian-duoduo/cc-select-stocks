import Foundation

struct AppConfig {
    static var baseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
            ?? "http://8.163.91.16:5000/api/v1"
    }

    static var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String
            ?? "select-stocks-2024"
    }
}
