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

    // 处理可能为字符串的数值字段
    enum CodingKeys: String, CodingKey {
        case code, name, price, change_pct, selected_at
        case holders_trend, change_5y, price_percentile, chip_concentration
        case macd_divergence, trend_analysis, price_position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        name = try container.decode(String.self, forKey: .name)
        selected_at = try container.decodeIfPresent(String.self, forKey: .selected_at)

        // 处理可能为字符串的数值字段
        price = try Self.decodeNumeric(container: container, key: .price)
        change_pct = try Self.decodeNumeric(container: container, key: .change_pct)
        change_5y = try Self.decodeNumeric(container: container, key: .change_5y)
        price_percentile = try Self.decodeNumeric(container: container, key: .price_percentile)
        chip_concentration = try Self.decodeNumeric(container: container, key: .chip_concentration)
        price_position = try Self.decodeNumeric(container: container, key: .price_position)

        holders_trend = try container.decodeIfPresent([HolderData].self, forKey: .holders_trend)
        macd_divergence = try container.decodeIfPresent(MACDDivergence.self, forKey: .macd_divergence)
        trend_analysis = try container.decodeIfPresent(TrendAnalysis.self, forKey: .trend_analysis)
    }

    private static func decodeNumeric(container: KeyedDecodingContainer<Stock.CodingKeys>, key: CodingKeys) throws -> Double? {
        if let doubleValue = try? container.decode(Double.self, forKey: key) {
            return doubleValue
        }
        if let stringValue = try? container.decode(String.self, forKey: key), let doubleValue = Double(stringValue) {
            return doubleValue
        }
        return nil
    }
}

struct StockResponse: Codable {
    let code: Int
    let data: [Stock]?
    let message: String?
    let total: Int?
}