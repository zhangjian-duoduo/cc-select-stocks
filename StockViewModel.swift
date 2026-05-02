import Foundation
import Combine
import SwiftUI

struct AppConfig {
    static let baseURL = "http://8.163.91.16:5000/api/v1"
}

enum SortOption: String, CaseIterable {
    case position = "位置"
    case score = "评分"
    case chip = "筹码"
    case shareholder = "股东"
    case dailyChange = "涨跌"
    case change5Y = "5年涨跌"
    case bottomDivergence = "底背离"
    case yoy = "同比"
    case qoq = "环比"
    case roe = "ROE"
}

@MainActor
class StockViewModel: ObservableObject {
    @Published var stocks: [Stock] = []
    @Published var filteredStocks: [Stock] = []
    private(set) var allStocks: [Stock] = []  // 完整股票列表，不受筛选影响
    @Published var financialUpdateStocks: [Stock] = []  // 今日财务数据更新的股票
    @Published var isLoading = false
    @Published var isLoadingFinancialUpdates = false
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

    // 记录股票添加到自选的时间 [股票代码: 添加日期]
    @Published var favoriteDates: [String: Date] = [:] {
        didSet {
            saveFavoriteDates()
        }
    }

    // 记录添加到自选时的价格 [股票代码: 价格]
    @Published var favoriteEntryPrices: [String: Double] = [:] {
        didSet {
            saveFavoriteEntryPrices()
        }
    }

    // 缓存自选股的名称和最新价格，保证列表里没该股票时也能正常显示
    @Published var favoriteStockData: [String: CachedStockData] = [:] {
        didSet {
            saveFavoriteStockData()
        }
    }

    // 保存当前活跃的筛选条件（在FilterView中设置）
    private var skipFilterApply = false
    @Published var activeFilters: Set<String> = [] {
        didSet {
            saveFilters()
            if !activeFilters.isEmpty && !skipFilterApply {
                Task {
                    await applyServerFilters(activeFilters)
                }
            }
            skipFilterApply = false
        }
    }

    /// 保存筛选条件但不触发重复的 API 调用（FilterView 已直接调用并设置结果）
    func saveFiltersDirectly(_ filters: Set<String>) {
        skipFilterApply = true
        activeFilters = filters
    }

    func clearFilters() {
        skipFilterApply = true
        activeFilters = []
    }

    private let baseURL = AppConfig.baseURL
    private let favoritesKey = "favorited_stocks"
    private let filtersKey = "active_filters"
    private let filtersLastAppliedKey = "filters_last_applied"
    private let sessionStartKey = "session_start"
    private let favoriteDatesKey = "favorite_dates"
    private let favoriteEntryPricesKey = "favorite_entry_prices"
    private let favoriteStockDataKey = "favorite_stock_data"

    init() {
        loadFavorites()
        loadFavoriteDates()
        loadFavoriteEntryPrices()
        loadFavoriteStockData()
        loadStoredFilters()
        // 记录本次会话开始时间（必须在 loadStoredFilters 之后，否则筛选条件会被清掉）
        UserDefaults.standard.set(Date(), forKey: sessionStartKey)
        loadPositions()
        loadTrades()
        Task {
            await loadData()
            await updatePrices()
            await loadFinancialUpdates()
            // 启动时不自动应用筛选，让用户自己选择
        }
    }

    private func loadFavoriteEntryPrices() {
        if let saved = UserDefaults.standard.dictionary(forKey: favoriteEntryPricesKey) as? [String: Double] {
            favoriteEntryPrices = saved
        }
    }

    private func saveFavoriteEntryPrices() {
        UserDefaults.standard.set(favoriteEntryPrices, forKey: favoriteEntryPricesKey)
    }

    private func loadFavoriteStockData() {
        if let data = UserDefaults.standard.data(forKey: favoriteStockDataKey),
           let saved = try? JSONDecoder().decode([String: CachedStockData].self, from: data) {
            favoriteStockData = saved
        }
    }

    private func saveFavoriteStockData() {
        if let data = try? JSONEncoder().encode(favoriteStockData) {
            UserDefaults.standard.set(data, forKey: favoriteStockDataKey)
        }
    }

    // 用最新数据更新自选股缓存
    private func refreshFavoriteStockData() {
        for code in favorites {
            if let stock = allStocks.first(where: { $0.code == code }),
               let price = stock.price {
                favoriteStockData[code] = CachedStockData(name: stock.name, price: price)
            }
        }
    }

    // 补全不在选股列表中的自选股数据
    private func fetchMissingFavorites() async {
        let missingCodes = favorites.filter { code in
            !allStocks.contains(where: { $0.code == code })
        }
        guard !missingCodes.isEmpty else { return }

        guard let url = URL(string: "\(baseURL)/stocks/batch") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        do {
            let body = ["codes": Array(missingCodes)]
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let respCode = json["code"] as? Int, respCode == 0,
                  let batchData = json["data"] as? [String: Any] else { return }

            for (code, itemValue) in batchData {
                guard var itemDict = itemValue as? [String: Any] else { continue }
                // 确保code字段存在
                if itemDict["code"] == nil {
                    itemDict["code"] = code
                }
                // 将字典转为JSON data，再通过Stock的Codable解码
                let itemData = try JSONSerialization.data(withJSONObject: itemDict)
                if let stock = try? JSONDecoder().decode(Stock.self, from: itemData) {
                    allStocks.append(stock)
                }
                // 同时更新缓存
                let name = itemDict["name"] as? String ?? code
                let price = itemDict["price"] as? Double ?? favoriteEntryPrices[code] ?? 0
                favoriteStockData[code] = CachedStockData(name: name, price: price)
            }
            // 重新刷新自选股缓存，让 allStocks 中新增的股票被同步
            refreshFavoriteStockData()
        } catch {
            print("补全自选股数据失败: \(error)")
        }
    }

    private func loadFavoriteDates() {
        if let saved = UserDefaults.standard.dictionary(forKey: favoriteDatesKey) as? [String: TimeInterval] {
            favoriteDates = saved.mapValues { Date(timeIntervalSince1970: $0) }
        }
    }

    private func saveFavoriteDates() {
        let timeIntervals = favoriteDates.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(timeIntervals, forKey: favoriteDatesKey)
    }

    // 添加到自选
    func addToFavorites(_ code: String) {
        favorites.insert(code)
        // 记录添加时间和当前价格
        if favoriteDates[code] == nil {
            favoriteDates[code] = Date()
        }
        // 记录添加时的价格，并缓存名称+价格
        if let stock = allStocks.first(where: { $0.code == code }),
           let price = stock.price {
            favoriteEntryPrices[code] = price
            favoriteStockData[code] = CachedStockData(name: stock.name, price: price)
        }
    }

    // 从自选移除
    func removeFromFavorites(_ code: String) {
        favorites.remove(code)
        // 保留添加日期和价格记录（用于计算历史）
    }

    // 计算加入自选后的涨跌幅
    func calculateFavoriteReturn(_ code: String) -> Double? {
        guard let entryPrice = favoriteEntryPrices[code],
              let stock = stocks.first(where: { $0.code == code }),
              let currentPrice = stock.price,
              entryPrice > 0 else {
            return nil
        }
        return (currentPrice - entryPrice) / entryPrice * 100
    }

    // ========== 模拟交易功能 ==========
    @Published var positions: [String: Position] = [:]
    @Published var trades: [Trade] = []

    private let positionsKey = "virtual_positions"
    private let tradesKey = "virtual_trades"

    private func loadPositions() {
        if let data = UserDefaults.standard.data(forKey: positionsKey),
           let saved = try? JSONDecoder().decode([String: Position].self, from: data) {
            positions = saved
        }
    }

    private func savePositions() {
        if let data = try? JSONEncoder().encode(positions) {
            UserDefaults.standard.set(data, forKey: positionsKey)
        }
    }

    private func loadTrades() {
        if let data = UserDefaults.standard.data(forKey: tradesKey),
           let saved = try? JSONDecoder().decode([Trade].self, from: data) {
            trades = saved
        }
    }

    private func saveTrades() {
        if let data = try? JSONEncoder().encode(trades) {
            UserDefaults.standard.set(data, forKey: tradesKey)
        }
    }

    // 买入股票
    func buyStock(code: String, name: String, price: Double, quantity: Int) {
        // 记录交易
        let trade = Trade(
            code: code,
            name: name,
            price: price,
            quantity: quantity,
            isBuy: true,
            timeIntervalSince1970: Date().timeIntervalSince1970
        )
        trades.append(trade)

        // 更新持仓
        if var position = positions[code] {
            // 追加买入
            let totalCost = position.avgCost * Double(position.quantity) + price * Double(quantity)
            position.quantity += quantity
            position.avgCost = totalCost / Double(position.quantity)
            positions[code] = position
        } else {
            // 新建持仓
            positions[code] = Position(
                code: code,
                name: name,
                quantity: quantity,
                avgCost: price,
                firstBuyDate: Date()
            )
        }

        saveTrades()
        savePositions()
    }

    // 卖出股票，返回是否成功
    @discardableResult
    func sellStock(code: String, price: Double, quantity: Int) -> Bool {
        guard var position = positions[code], position.quantity >= quantity else { return false }

        // 记录交易
        let trade = Trade(
            code: code,
            name: position.name,
            price: price,
            quantity: quantity,
            isBuy: false,
            timeIntervalSince1970: Date().timeIntervalSince1970
        )
        trades.append(trade)

        // 更新持仓
        position.quantity -= quantity
        if position.quantity == 0 {
            positions.removeValue(forKey: code)
        } else {
            positions[code] = position
        }

        saveTrades()
        savePositions()
        return true
    }

    // 获取持仓
    func getPosition(_ code: String) -> Position? {
        positions[code]
    }

    // 获取所有持仓列表（按实时收益率排序）
    var positionList: [Position] {
        Array(positions.values).sorted { a, b in
            let p0 = allStocks.first(where: { s in s.code == a.code })?.price ?? a.currentPrice
            let p1 = allStocks.first(where: { s in s.code == b.code })?.price ?? b.currentPrice
            return a.realTimeReturnPct(p0) > b.realTimeReturnPct(p1)
        }
    }

    // 更新持仓的当前价格（用于计算盈亏）
    func updatePositionPrices() {
        for (code, var position) in positions {
            if let stock = allStocks.first(where: { $0.code == code }),
               let price = stock.price {
                position.currentPrice = price
                positions[code] = position
            }
        }
    }

    // 总盈亏（实时价格计算）
    var totalReturn: Double {
        positions.values.reduce(0) { acc, pos in
            let price = allStocks.first(where: { s in s.code == pos.code })?.price ?? pos.currentPrice
            return acc + pos.realTimePositionReturn(price)
        }
    }

    // 总收益率（实时价格计算）
    var totalReturnPct: Double {
        let totalCost = positions.values.reduce(0.0) { $0 + $1.totalCost }
        guard totalCost > 0 else { return 0 }
        return totalReturn / totalCost * 100
    }

    private func loadStoredFilters() {
        // 从存储加载筛选条件（在筛选页面应用后会保存）
        // 启动时检查是否需要应用，如果筛选标记存在
        if let savedFilters = UserDefaults.standard.array(forKey: filtersKey) as? [String],
           let lastApplied = UserDefaults.standard.object(forKey: filtersLastAppliedKey) as? Date {
            // 如果筛选是在当前会话保存的，则加载
            let sessionStart = UserDefaults.standard.object(forKey: sessionStartKey) as? Date ?? Date()
            if lastApplied > sessionStart {
                activeFilters = Set(savedFilters)
            } else {
                // 上次筛选不是在本次会话应用的，清除
                UserDefaults.standard.removeObject(forKey: filtersKey)
                UserDefaults.standard.removeObject(forKey: filtersLastAppliedKey)
            }
        }
    }

    private func saveFilters() {
        UserDefaults.standard.set(Array(activeFilters), forKey: filtersKey)
        UserDefaults.standard.set(Date(), forKey: filtersLastAppliedKey)
        UserDefaults.standard.set(Date(), forKey: sessionStartKey)
        print("保存筛选条件: \(Array(activeFilters))")
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
                self.allStocks = stockResponse.data ?? []
                self.stocks = self.allStocks
                self.refreshFavoriteStockData()
                self.applySort()
                self.errorMessage = nil
                // 补全不在选股列表中的自选股数据
                await self.fetchMissingFavorites()
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

    // 调用后端API应用筛选
    func applyServerFilters(_ filters: Set<String>) async {
        guard !filters.isEmpty else {
            stocks = allStocks
            applySort()
            return
        }
        print("applyServerFilters: \(filters)")

        guard let url = URL(string: "\(baseURL)/filter") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        do {
            let body = ["filters": Array(filters)]
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let result = try JSONDecoder().decode(StockResponse.self, from: data)
                if result.code == 0 {
                    print("筛选成功: \(result.data?.count ?? 0) 只")
                    self.stocks = result.data ?? []
                    self.applySort()
                } else {
                    print("筛选失败: \(result.message ?? "未知错误")")
                }
            }
        } catch {
            print("应用筛选失败: \(error)")
        }
    }

    func refresh() async {
        // 保存当前筛选条件
        let savedFilters = activeFilters
        await loadData()
        await updatePrices()
        await loadFinancialUpdates()
        // 如果有保存的筛选条件，重新应用
        if !savedFilters.isEmpty {
            await applyServerFilters(savedFilters)
        }
    }

    // 加载今日财务数据有更新的股票
    func loadFinancialUpdates() async {
        isLoadingFinancialUpdates = true
        errorMessage = nil

        guard let url = URL(string: "\(baseURL)/financial_updates") else {
            errorMessage = "URL错误"
            isLoadingFinancialUpdates = false
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "无效响应"
                isLoadingFinancialUpdates = false
                return
            }

            guard httpResponse.statusCode == 200 else {
                errorMessage = "服务器错误: \(httpResponse.statusCode)"
                isLoadingFinancialUpdates = false
                return
            }

            let decoder = JSONDecoder()
            let result = try decoder.decode(FinancialUpdatesResponse.self, from: data)
            if result.code == 0, let data = result.data {
                self.financialUpdateStocks = data.stocks ?? []
                print("今日有 \(self.financialUpdateStocks.count) 只股票财务数据更新")
            }
        } catch {
            print("财务更新加载失败: \(error)")
        }

        isLoadingFinancialUpdates = false
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

    func applySort() {
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
        case .yoy:
            // 净利润同比
            guard let yoy = stock.net_profit_yoy else { return 0 }
            let clean = yoy.replacingOccurrences(of: "%", with: "")
            return Double(clean) ?? 0
        case .qoq:
            // 净利润环比
            guard let qoq = stock.net_profit_qoq else { return 0 }
            let clean = qoq.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")
            return Double(clean) ?? 0
        case .roe:
            // ROE
            guard let roe = stock.roe else { return 0 }
            let clean = roe.replacingOccurrences(of: "%", with: "")
            return Double(clean) ?? 0
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

    func calculateScore(_ stock: Stock) -> Double {
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

    func trendScoreValue(_ trend: Stock.TrendAnalysis?) -> Double {
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
            let price = stock.price ?? allStocks.first(where: { $0.code == stock.code })?.price
            if let price = price {
                favoriteEntryPrices[stock.code] = price
                favoriteStockData[stock.code] = CachedStockData(name: stock.name, price: price)
            }
            if favoriteDates[stock.code] == nil {
                favoriteDates[stock.code] = Date()
            }
        }
    }

    var favoritedStocks: [Stock] {
        favorites.compactMap { code in
            // 优先从完整列表中查找，不受筛选影响
            if let stock = allStocks.first(where: { $0.code == code }) {
                return stock
            }
            // 不在完整列表中，用缓存数据显示
            if let cached = favoriteStockData[code] {
                return Stock(code: code, name: cached.name, price: cached.price, change_pct: nil)
            }
            // 连缓存都没有（从未成功加载过），用收藏时的价格
            return Stock(
                code: code,
                name: "未知",
                price: favoriteEntryPrices[code],
                change_pct: nil
            )
        }
    }
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

// 筛选响应
struct FilterResponse: Codable {
    let code: Int
    let message: String?
    let data: [Stock]?
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

// 批量查询股票响应
struct BatchStockResponse: Codable {
    let code: Int
    let data: [String: BatchStockItem]?
}

struct BatchStockItem: Codable {
    let code: String
    let name: String?
    let price: Double?
    let change_pct: Double?
}