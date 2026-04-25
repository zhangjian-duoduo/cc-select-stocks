import Foundation
import Combine
import SwiftUI

enum SortOption: String, CaseIterable {
    case position = "位置"
    case score = "评分"
    case chip = "筹码"
    case shareholder = "股东"
    case bottomDivergence = "底背离"
    case dailyChange = "当日涨跌"
    case change5Y = "5年涨跌"
}

class StockViewModel: ObservableObject {
    @Published var stocks: [Stock] = []
    @Published var filteredStocks: [Stock] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var sortOption: SortOption = .position
    @Published var sortAscending: Bool = false
    @Published var searchText: String = "" {
        didSet {
            applySearch()
        }
    }
    @Published var favorites: Set<String> = [] {
        didSet {
            saveFavorites()
        }
    }

    private let baseURL = "http://8.163.91.16:5000/api/v1"
    private let favoritesKey = "favorited_stocks"

    init() {
        loadFavorites()
        Task {
            await loadData()
            await updatePrices()  // 打开app时自动更新价格
        }
    }

    private func loadFavorites() {
        if let savedFavorites = UserDefaults.standard.array(forKey: favoritesKey) as? [String] {
            favorites = Set(savedFavorites)
        }
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favorites), forKey: favoritesKey)
    }

    // 更新实时价格
    @MainActor
    func updatePrices() async {
        guard let url = URL(string: "\(baseURL)/update_prices") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("价格更新成功")
            }
        } catch {
            print("价格更新失败: \(error)")
        }
    }

    @MainActor
    func loadData() async {
        isLoading = true
        errorMessage = nil

        guard let url = URL(string: "\(baseURL)/stocks?page_size=500") else {
            errorMessage = "URL错误"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // 调试：打印响应长度
            print("收到数据: \(data.count) bytes")

            // 打印前500个字符的JSON用于调试
            if let jsonString = String(data: data, encoding: .utf8) {
                print("JSON预览: \(String(jsonString.prefix(500)))")
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "无效响应"
                isLoading = false
                return
            }

            guard httpResponse.statusCode == 200 else {
                errorMessage = "服务器错误: \(httpResponse.statusCode)"
                isLoading = false
                return
            }

            let stockResponse = try JSONDecoder().decode(StockResponse.self, from: data)
            if stockResponse.code == 0 {
                self.stocks = stockResponse.data ?? []
                self.applySort()
                self.errorMessage = nil
            } else {
                self.errorMessage = "API错误: \(stockResponse.message ?? "未知错误")"
            }
        } catch let error as DecodingError {
            // 详细解析错误
            switch error {
            case .keyNotFound(let key, _):
                self.errorMessage = "缺少字段: \(key.stringValue)"
            case .typeMismatch(let type, let context):
                let debugDescription = context.debugDescription
                self.errorMessage = "类型不匹配: \(type) - \(debugDescription)"
            case .valueNotFound(let type, _):
                self.errorMessage = "值为空: \(type)"
            default:
                self.errorMessage = "数据解析错误: \(error.localizedDescription)"
            }
            // 打印原始错误用于调试
            print("JSON解析错误: \(error)")
        } catch {
            self.errorMessage = "网络错误: \(error.localizedDescription)"
        }

        isLoading = false
    }

    @MainActor
    func refresh() async {
        await loadData()
    }

    func toggleSort(_ option: SortOption) {
        if sortOption == option {
            sortAscending.toggle()
        } else {
            sortOption = option
            sortAscending = false
        }
        applySort()
    }

    private func applySort() {
        let sorted = stocks.sorted { stock1, stock2 in
            let value1 = sortValue(for: stock1)
            let value2 = sortValue(for: stock2)
            return sortAscending ? value1 < value2 : value1 > value2
        }
        filteredStocks = sorted
        // Re-apply search after sort change
        applySearch()
    }

    private func applySearch() {
        let baseList: [Stock]
        if searchText.isEmpty {
            baseList = stocks
        } else {
            let query = searchText.lowercased()
            baseList = stocks.filter { stock in
                stock.code.lowercased().contains(query) ||
                stock.name.lowercased().contains(query)
            }
        }

        // Apply sort
        let sorted = baseList.sorted { stock1, stock2 in
            let value1 = sortValue(for: stock1)
            let value2 = sortValue(for: stock2)
            return sortAscending ? value1 < value2 : value1 > value2
        }
        filteredStocks = sorted
    }

    private func sortValue(for stock: Stock) -> Double {
        switch sortOption {
        case .position:
            return stock.price_position ?? 1.0
        case .score:
            return calculateScore(stock)
        case .chip:
            return stock.chip_concentration ?? 0
        case .shareholder:
            // 股东人数变化百分比（5年趋势）
            // 数据已按旧→新排列，所以first是最旧的，last是最新的
            guard let trend = stock.holders_trend, trend.count >= 2 else { return 0 }
            // 过滤异常数据（股东数<1000可能是上市初期数据）
            let validTrend = trend.filter { ($0.holders ?? 0) >= 1000 }
            guard validTrend.count >= 2 else { return 0 }
            let oldest = validTrend.first?.holders ?? 0
            let newest = validTrend.last?.holders ?? 0
            if oldest > 0 {
                return Double(newest - oldest) / Double(oldest) * 100
            }
            return 0
        case .bottomDivergence:
            // 有任何背离返回1，否则0
            return (stock.macd_divergence?.daily == true || stock.macd_divergence?.weekly == true || stock.macd_divergence?.monthly == true) ? 1 : 0
        case .dailyChange:
            // 当日涨跌幅
            return stock.change_pct ?? 0
        case .change5Y:
            // 5年涨跌幅
            return stock.change_5y ?? 0
        }
    }

    // 计算股东人数变化百分比
    func shareholderChangePercent(_ stock: Stock) -> Double {
        // 数据已按旧→新排列，所以first是最旧的，last是最新的
        // 过滤异常数据（股东数<1000可能是上市初期数据）
        guard let trend = stock.holders_trend, trend.count >= 2 else { return 0 }
        let validTrend = trend.filter { ($0.holders ?? 0) >= 1000 }
        guard validTrend.count >= 2 else { return 0 }
        let oldest = validTrend.first?.holders ?? 0
        let newest = validTrend.last?.holders ?? 0
        if oldest > 0 {
            return Double(newest - oldest) / Double(oldest) * 100
        }
        return 0
    }

    // 获取背离级别文本
    func divergenceText(_ stock: Stock) -> String {
        guard let div = stock.macd_divergence else { return "-" }
        var levels: [String] = []
        if div.daily == true { levels.append("日") }
        if div.weekly == true { levels.append("周") }
        if div.monthly == true { levels.append("月") }
        return levels.isEmpty ? "-" : levels.joined(separator: "/")
    }

    private func calculateScore(_ stock: Stock) -> Double {
        // 优化后的评分算法
        // 核心逻辑：低估值+高筹码集中+趋势向上+底背离 = 高分

        // 1. 趋势得分 (30%) - 短期趋势最重要
        let trendScore = trendScoreValue(stock.trend_analysis)

        // 2. 估值得分 (25%) - 价格分位越低越好
        let pricePct = stock.price_percentile ?? 50
        let valuationScore = (100 - pricePct) / 100.0

        // 3. 筹码得分 (20%) - 筹码集中度越高越好
        let chipVal = stock.chip_concentration ?? 50
        let chipScore = chipVal / 100.0

        // 4. 股东变化得分 (15%) - 股东人数减少说明筹码集中
        let holderChange = shareholderChangePercent(stock)
        let holderScore: Double
        if holderChange < -10 {
            holderScore = 1.0  // 股东减少>10%，高分
        } else if holderChange < 0 {
            holderScore = 0.7
        } else if holderChange < 20 {
            holderScore = 0.4
        } else {
            holderScore = 0.1  // 股东大幅增加，低分
        }

        // 5. 背离得分 (10%) - 有底背离是加分项
        var divergenceScore: Double = 0
        if stock.macd_divergence?.monthly == true { divergenceScore += 0.5 }
        if stock.macd_divergence?.weekly == true { divergenceScore += 0.3 }
        if stock.macd_divergence?.daily == true { divergenceScore += 0.2 }

        // 综合评分
        let total = trendScore * 0.30 + valuationScore * 0.25 + chipScore * 0.20 + holderScore * 0.15 + divergenceScore * 0.10
        return min(1.0, max(0.0, total))
    }

    private func trendScoreValue(_ trend: Stock.TrendAnalysis?) -> Double {
        guard let t = trend else { return 0.5 }
        // 短期趋势权重最高
        switch t.short {
        case "上涨趋势": return 1.0
        case "震荡": return 0.6
        case "下跌趋势": return 0.2
        default: return 0.5
        }
    }

    private func trendConfidence(_ trend: Stock.TrendAnalysis?) -> Double {
        guard let t = trend else { return 50 }
        switch t.short {
        case "上涨趋势": return 80
        case "震荡": return 50
        case "下跌趋势": return 20
        default: return 50
        }
    }

    // 自选股功能
    func isFavorited(_ code: String) -> Bool {
        return favorites.contains(code)
    }

    func toggleFavorite(_ stock: Stock) {
        if favorites.contains(stock.code) {
            favorites.remove(stock.code)
        } else {
            favorites.insert(stock.code)
        }
    }

    var favoritedStocks: [Stock] {
        stocks.filter { favorites.contains($0.code) }
    }
}