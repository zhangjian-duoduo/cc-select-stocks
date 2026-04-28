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
    var kline: [KlineData]?
    var kline_daily: [KlineData]?
    var kline_weekly: [KlineData]?
    var kline_monthly: [KlineData]?

    // 财务数据
    var net_profit_yoy: String?  // 净利润同比
    var net_profit_qoq: String?  // 净利润环比
    var revenue: String?         // 营业收入
    var book_value_per_share: String?  // 每股净资产
    var roe: String?             // ROE
    var sector: String?          // 所属行业板块
    var financial_updated_at: String?  // 财务数据更新时间

    struct HolderData: Codable {
        var date: String?
        var holders: Int?
    }

    // 历史财务数据
    var financial_history: [FinancialHistoryItem]?

    struct FinancialHistoryItem: Codable {
        var report_date: String?
        var report_name: String?
        var quarter: String?
        var net_profit_yoy: String?
        var net_profit_qoq: String?
        var revenue_yoy: String?
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

    struct KlineData: Codable {
        var date: String?
        var open: Double?
        var high: Double?
        var low: Double?
        var close: Double?
        var volume: Double?
    }

    // 处理可能为字符串的数值字段
    enum CodingKeys: String, CodingKey {
        case code, name, price, change_pct, selected_at
        case holders_trend, change_5y, price_percentile, chip_concentration
        case macd_divergence, trend_analysis, price_position, kline
        case kline_daily, kline_weekly, kline_monthly
        case net_profit_yoy, net_profit_qoq, revenue, book_value_per_share, roe, sector
        case financial_updated_at
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
        kline = try container.decodeIfPresent([KlineData].self, forKey: .kline)
        kline_daily = try container.decodeIfPresent([KlineData].self, forKey: .kline_daily)
        kline_weekly = try container.decodeIfPresent([KlineData].self, forKey: .kline_weekly)
        kline_monthly = try container.decodeIfPresent([KlineData].self, forKey: .kline_monthly)

        // 财务数据
        net_profit_yoy = try container.decodeIfPresent(String.self, forKey: .net_profit_yoy)
        net_profit_qoq = try container.decodeIfPresent(String.self, forKey: .net_profit_qoq)
        roe = try container.decodeIfPresent(String.self, forKey: .roe)
        sector = try container.decodeIfPresent(String.self, forKey: .sector)
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

// 手动解析API响应 - 支持数组和对象两种格式
struct StockAPI {
    // 解析列表页响应（data是数组）
    static func parseListResponse(_ data: Data) -> [Stock] {
        do {
            let response = try JSONDecoder().decode(StockResponse.self, from: data)
            return response.data ?? []
        } catch {
            print("解析列表失败: \(error)")
            return []
        }
    }

    // 解析详情页响应（data是对象）
    static func parseDetailResponse(_ data: Data) -> Stock? {
        do {
            // 手动解析JSON
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var dataField = json["data"] as? [String: Any] else {
                print("解析详情失败: data字段格式错误")
                return nil
            }

            // 处理JSON字符串字段
            // holders_trend可能是字符串
            if let holdersStr = dataField["holders_trend"] as? String {
                if let holdersData = holdersStr.data(using: .utf8),
                   let holdersArray = try? JSONSerialization.jsonObject(with: holdersData) as? [[String: Any]] {
                    dataField["holders_trend"] = holdersArray
                }
            }

            // macd_divergence可能是字符串
            if let macdStr = dataField["macd_divergence"] as? String {
                if let macdData = macdStr.data(using: .utf8),
                   let macdDict = try? JSONSerialization.jsonObject(with: macdData) as? [String: Any] {
                    dataField["macd_divergence"] = macdDict
                }
            }

            // trend_analysis可能是字符串
            if let trendStr = dataField["trend_analysis"] as? String {
                if let trendData = trendStr.data(using: .utf8),
                   let trendDict = try? JSONSerialization.jsonObject(with: trendData) as? [String: Any] {
                    dataField["trend_analysis"] = trendDict
                }
            }

            // 处理kline_daily/kline_weekly/kline_monthly（可能是字符串）
            for key in ["kline_daily", "kline_weekly", "kline_monthly"] {
                if let klineStr = dataField[key] as? String {
                    if let klineData = klineStr.data(using: .utf8),
                       let klineArray = try? JSONSerialization.jsonObject(with: klineData) as? [[String: Any]] {
                        dataField[key] = klineArray
                    }
                }
            }

            // 将处理后的data转为JSON Data
            let dataJSON = try JSONSerialization.data(withJSONObject: dataField)
            let stock = try JSONDecoder().decode(Stock.self, from: dataJSON)
            return stock
        } catch {
            print("解析详情失败: \(error)")
            return nil
        }
    }
}