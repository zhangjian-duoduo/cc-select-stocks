import Foundation

enum SelectionType: String, CaseIterable {
    case standard = "智能选股"
    case newRule = "新规"
}

// 多自选股列表模型
struct Watchlist: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var stockCodes: [String]
    var createdAt: Date = Date()

    static func == (lhs: Watchlist, rhs: Watchlist) -> Bool {
        lhs.id == rhs.id
    }
}

struct Stock: Identifiable, Codable {
    var id: String { code }
    let code: String
    let name: String
    var price: Double?
    var change_pct: Double?
    var selected_at: String?

    // 手动添加的构造函数（用于创建简单Stock对象）
    init(code: String, name: String, price: Double?, change_pct: Double?) {
        self.code = code
        self.name = name
        self.price = price
        self.change_pct = change_pct
        self.concepts = nil
        self.surge_reason = nil
        self.surge_concept = nil
    }

    // 额外分析数据
    var holders_trend: [HolderData]?
    var change_5y: Double?
    var price_percentile: Double?
    var pe_ttm: Double?
    var pe_percentile: Double?
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
    var revenue: String?         // 营业收入（如 "2334.33亿"）
    var book_value_per_share: Double?  // 每股净资产
    var roe: String?             // ROE
    var sector: String?          // 所属行业板块
    var financial_updated_at: String?  // 财务数据更新时间
    var total_market_cap: Double?   // 总市值（元）
    var dividend_count: Int?        // 累计分红次数
    var other_receivables_ratio: Double?  // 其他应收款/总资产(%)
    var fund_embezzlement_risk: Double?   // 资金占用风险 1=高风险
    var financial_fraud_risk: Double?     // 财务造假风险 1=有处罚 2=有造假相关处罚
    var debt_ratio: Double?              // 资产负债率(%)
    var operating_cash_flow: Double?     // 经营性现金流
    var rd_ratio: Double?                // 研发费用率(%)

    // 概念板块
    var concepts: [String]?       // 所属概念板块列表
    var surge_reason: String?     // 大涨原因（如 "面板板块领涨+3.5%"）
    var surge_concept: String?    // 驱动概念名称

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
        case holders_trend, change_5y, price_percentile, pe_ttm, pe_percentile, chip_concentration
        case macd_divergence, trend_analysis, price_position, kline
        case kline_daily, kline_weekly, kline_monthly
        case net_profit_yoy, net_profit_qoq, roe, sector, revenue, book_value_per_share
        case financial_updated_at, total_market_cap, dividend_count
        case other_receivables_ratio, fund_embezzlement_risk, financial_fraud_risk
        case debt_ratio, operating_cash_flow, rd_ratio
        case concepts, surge_reason, surge_concept
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
        pe_ttm = try Self.decodeNumeric(container: container, key: .pe_ttm)
        pe_percentile = try Self.decodeNumeric(container: container, key: .pe_percentile)
        chip_concentration = try Self.decodeNumeric(container: container, key: .chip_concentration)
        price_position = try Self.decodeNumeric(container: container, key: .price_position)
        book_value_per_share = try Self.decodeNumeric(container: container, key: .book_value_per_share)

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
        revenue = try container.decodeIfPresent(String.self, forKey: .revenue)
        sector = try container.decodeIfPresent(String.self, forKey: .sector)
        total_market_cap = try Self.decodeNumeric(container: container, key: .total_market_cap)
        if let divDouble = try Self.decodeNumeric(container: container, key: .dividend_count) {
            dividend_count = Int(divDouble)
        }
        other_receivables_ratio = try Self.decodeNumeric(container: container, key: .other_receivables_ratio)
        fund_embezzlement_risk = try Self.decodeNumeric(container: container, key: .fund_embezzlement_risk)
        financial_fraud_risk = try Self.decodeNumeric(container: container, key: .financial_fraud_risk)
        debt_ratio = try Self.decodeNumeric(container: container, key: .debt_ratio)
        operating_cash_flow = try Self.decodeNumeric(container: container, key: .operating_cash_flow)
        rd_ratio = try Self.decodeNumeric(container: container, key: .rd_ratio)
        financial_updated_at = try container.decodeIfPresent(String.self, forKey: .financial_updated_at)

        concepts = try container.decodeIfPresent([String].self, forKey: .concepts)
        surge_reason = try container.decodeIfPresent(String.self, forKey: .surge_reason)
        surge_concept = try container.decodeIfPresent(String.self, forKey: .surge_concept)
    }

    private static func decodeNumeric(container: KeyedDecodingContainer<Stock.CodingKeys>, key: CodingKeys) throws -> Double? {
        try container.decodeNumeric(key: key)
    }
}

struct StockResponse: Codable {
    let code: Int
    let data: [Stock]?
    let message: String?
    let total: Int?
}

// 动态选股筛选响应
struct ScreeningResponse: Codable {
    let code: Int
    let data: [Stock]?
    let message: String?
    let total: Int?
    let stats: ScreeningStats?
}

struct ScreeningStats: Codable {
    let total_scanned: Int?
}

// 筛选条件模型（UI 使用）
struct ScreeningCondition: Identifiable {
    let id: String          // API 字段名
    let title: String
    let subtitle: String
    let section: ScreeningSection
}

enum ScreeningSection: String, CaseIterable {
    case safety = "安全过滤"
    case financial = "核心成长创新"
    case industry = "行业属性"
}

extension ScreeningCondition {
    static let all: [ScreeningCondition] = [
        .init(id: "listed_over_180d", title: "上市 > 180天", subtitle: "股票上市交易超过6个月", section: .safety),
        .init(id: "not_st", title: "非 ST", subtitle: "排除ST、*ST等风险警示股票", section: .safety),
        .init(id: "revenue_over_5yi", title: "营收 ≥ 5亿", subtitle: "最近年报营业收入不低于5亿元", section: .financial),
        .init(id: "revenue_yoy_over_25", title: "营收同比 ≥ 25%", subtitle: "最新报告期营收同比增长不低于25%", section: .financial),
        .init(id: "rd_ratio_over_10", title: "研发费用率 ≥ 10%", subtitle: "研发费用占营业收入比例不低于10%", section: .financial),
        .init(id: "rev_cagr_over_30", title: "营收3年CAGR ≥ 30%", subtitle: "近三年营收复合增长率不低于30%", section: .financial),
        .init(id: "debt_ratio_under_60", title: "资产负债率 ≤ 60%", subtitle: "资产负债率不超过60%", section: .financial),
        .init(id: "operating_cashflow_positive", title: "经营性现金流 > 0", subtitle: "最新报告期经营性现金流为正", section: .financial),
        .init(id: "inst_ownership_over_5", title: "机构持股 ≥ 5%", subtitle: "机构持股比例不低于5%", section: .financial),
        .init(id: "emerging_concept", title: "新兴产业概念", subtitle: "属于AI、机器人、新能源、半导体、军工等新兴产业", section: .industry),
    ]
}

struct EmptyResponse: Codable {
    let code: Int?
    let message: String?
}

struct BatchStockResponse: Codable {
    let code: Int
    let data: [String: Stock]?
    let message: String?
}

struct PriceInfo: Codable {
    let price: Double?
    let change_pct: Double?
}

struct LivePrice {
    let price: Double
    let changePct: Double?
}

struct PriceResponse: Codable {
    let code: Int
    let data: [String: PriceInfo]?
}

struct FinancialHistoryResponse: Codable {
    let code: Int
    let data: FinancialHistoryData?
}

struct FinancialHistoryData: Codable {
    let history: [Stock.FinancialHistoryItem]?
}

// 虚拟交易记录
struct Trade: Codable, Identifiable {
    var id: String { code + "_" + String(timeIntervalSince1970) }
    let code: String
    let name: String
    var price: Double      // 成交价格
    var quantity: Int      // 成交数量
    var isBuy: Bool       // true=买入, false=卖出
    var timeIntervalSince1970: TimeInterval  // 交易时间戳

    var totalAmount: Double {
        price * Double(quantity)
    }

    var date: Date {
        Date(timeIntervalSince1970: timeIntervalSince1970)
    }
}

// 虚拟持仓
struct Position: Codable, Identifiable {
    var id: String { code }
    let code: String
    let name: String
    var quantity: Int          // 持有数量
    var avgCost: Double         // 平均成本
    var firstBuyDate: Date?    // 首次买入日期

    var currentPrice: Double = 0  // 当前价格（外部设置）

    // 计算实时涨跌幅（需要传入当前价格）
    func realTimeReturnPct(_ currentPrice: Double) -> Double {
        guard avgCost > 0, quantity > 0, currentPrice > 0 else { return 0 }
        return (currentPrice - avgCost) / avgCost * 100
    }

    // 计算实时盈亏（需要传入当前价格）
    func realTimePositionReturn(_ currentPrice: Double) -> Double {
        guard currentPrice > 0, quantity > 0, avgCost > 0 else { return 0 }
        return (currentPrice - avgCost) * Double(quantity)
    }

    var totalCost: Double {
        avgCost * Double(quantity)
    }

    var positionReturn: Double {
        guard currentPrice > 0, quantity > 0, avgCost > 0 else { return 0 }
        return (currentPrice - avgCost) * Double(quantity)
    }

    var returnPct: Double {
        guard avgCost > 0, quantity > 0 else { return 0 }
        return (currentPrice - avgCost) / avgCost * 100
    }
}

// 手动解析API响应 - 支持数组和对象两种格式
extension KeyedDecodingContainer {
    func decodeNumeric(key: Key) throws -> Double? {
        if let doubleValue = try? decode(Double.self, forKey: key) {
            return doubleValue
        }
        if let stringValue = try? decode(String.self, forKey: key), let doubleValue = Double(stringValue) {
            return doubleValue
        }
        return nil
    }
}

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