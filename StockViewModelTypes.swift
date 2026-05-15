import Foundation

enum SortOption: String, CaseIterable {
    case change5Y = "5年"
    case position = "位置"
    case pe = "PE"
    case score = "评分"
    case chip = "筹码"
    case shareholder = "股东"
    case dailyChange = "涨跌"
    case bottomDivergence = "底背离"
    case yoy = "同比"
    case qoq = "环比"
    case roe = "ROE"
    case added = "添加时间"
}

// 财务更新API响应
struct FinancialUpdatesResponse: Codable {
    let code: Int
    let data: FinancialUpdatesData?
}

struct FinancialUpdatesData: Codable {
    let date: String?
    let count: Int?
    let stocks: [Stock]?
}

// 月份财务数据响应
struct MonthFinancialResponse: Codable {
    let code: Int
    let data: MonthFinancialData?
}

struct MonthFinancialData: Codable {
    let month: String?
    let dates: [DateCountItem]
}

struct DateCountItem: Codable {
    let date: String
    let count: Int
}

// 自选股缓存数据，用于列表里没有该股票时做降级显示
struct CachedStockData: Codable {
    let name: String
    let price: Double
}
