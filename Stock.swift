import Foundation

struct Stock: Identifiable, Codable {
    var id: String { code }
    let code: String
    let name: String
    var price: Double?
    var change_pct: Double?
    var selected_at: String?

    // 额外分析数据
    var holders_trend: [HolderData]?
    var change_5y: Double?
    var price_percentile: Double?
    var chip_concentration: Double?
    var macd_divergence: MACDDivergence?
    var trend_analysis: TrendAnalysis?
    var price_position: Double?

    struct HolderData: Codable {
        var date: String?
        var holders: Int?
    }

    struct MACDDivergence: Codable {
        var daily: Bool?
        var weekly: Bool?
        var monthly: Bool?
    }

    struct TrendAnalysis: Codable {
        var short: String?
        var medium: String?
        var long: String?
    }
}

struct StockResponse: Codable {
    let code: Int
    let data: [Stock]?
    let message: String?
    let total: Int?
}