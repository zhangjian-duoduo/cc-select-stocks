import Foundation
import Combine
import SwiftUI

class StockViewModel: ObservableObject {
    @Published var stocks: [Stock] = []
    @Published var filteredStocks: [Stock] = []
    private(set) var allStocks: [Stock] = [] {  // 完整股票列表，不受筛选影响
        didSet {
            // 数据变化时清除缓存强制重建（即使 count 相同，数据可能已更新）
            if scoreCache.count != allStocks.count || oldValue.first?.price != allStocks.first?.price {
                precomputeDerivedData()
            }
            allStocksDict = Dictionary(grouping: allStocks, by: { $0.code }).compactMapValues(\.first)
        }
    }
    private(set) var allStocksDict: [String: Stock] = [:]  // O(1) 查找
    @Published var financialUpdateStocks: [Stock] = []  // 今日财务数据更新的股票
    @Published var isLoading = false
    @Published var isLoadingFinancialUpdates = false
    @Published var errorMessage: String?

    // 实时价格轮询
    @Published var livePrices: [String: LivePrice] = [:]
    private var priceTimer: Timer?
    private var isPollingPrices = false
    private var pollingTask: Task<Void, Never>?
    private var pollingGeneration = 0

    // 自定义动态筛选
    @Published var screeningResults: [Stock] = []
    @Published var screeningStats: ScreeningStats?
    @Published var screeningTotal: Int = 0
    @Published var isCustomScreening = false
    @Published var selectionType: SelectionType = .standard {
        didSet {
            if oldValue != selectionType {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if let cached = self.loadCachedStocks(for: self.selectionType) {
                        self.allStocks = cached
                        self.stocks = cached
                        self.applySort()
                    }
                }
                Task { @MainActor [weak self] in
                    await self?.loadData()
                }
            }
        }
    }
    @Published var sortOption: SortOption = .position
    @Published var sortAscending: Bool = false
    @Published var watchlistSortOption: SortOption = .added
    @Published var watchlistSortAscending: Bool = false

    // 预计算缓存，避免 StockCard 逐行重复计算
    private(set) var scoreCache: [String: Double] = [:]
    private(set) var riskCache: [String: (level: String, detail: String)] = [:]
    private var pinyinCache: [String: String] = [:]

    /// stock data 加载后调用，预计算高频查询数据
    func precomputeDerivedData() {
        var scores: [String: Double] = [:]
        var risks: [String: (level: String, detail: String)] = [:]
        var pinyins: [String: String] = [:]
        for stock in allStocks {
            scores[stock.code] = calculateScore(stock)
            risks[stock.code] = computeRiskLevel(stock)
            pinyins[stock.code] = Self.pinyinInitials(stock.name)
        }
        scoreCache = scores
        riskCache = risks
        pinyinCache = pinyins
    }
    @Published var searchText: String = "" {
        didSet {
            applySearch()
        }
    }
    // 多自选列表
    @Published var watchlists: [Watchlist] = [] {
        didSet {
            saveWatchlists()
        }
    }
    @Published var selectedWatchlistId: String = "" {
        didSet {
            UserDefaults.standard.set(selectedWatchlistId, forKey: selectedWatchlistIdKey)
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

    // 缓存完整的 Stock 对象，用于不在 allStocks 中的自选股显示完整数据
    @Published var watchlistStockCache: [String: Stock] = [:] {
        didSet {
            saveWatchlistStockCache()
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

    let watchlistsKey = "watchlists_data"
    let selectedWatchlistIdKey = "selected_watchlist_id"
    let filtersKey = "active_filters"
    let filtersLastAppliedKey = "filters_last_applied"
    let sessionStartKey = "session_start"
    let favoriteDatesKey = "favorite_dates"
    let favoriteEntryPricesKey = "favorite_entry_prices"
    let favoriteStockDataKey = "favorite_stock_data"
    let cachedStocksKey = "cached_all_stocks"
    let watchlistStockCacheKey = "watchlist_stock_cache"

    init() {
        loadWatchlists()
        loadFavoriteDates()
        loadFavoriteEntryPrices()
        loadFavoriteStockData()
        loadWatchlistStockCache()
        loadStoredFilters()
        // 记录本次会话开始时间（必须在 loadStoredFilters 之后，否则筛选条件会被清掉）
        UserDefaults.standard.set(Date(), forKey: sessionStartKey)
        loadPositions()
        loadTrades()

        // 先尝试加载缓存数据，避免首次网络请求失败时列表为空
        if let cached = loadCachedStocks(for: selectionType) {
            allStocks = cached
            stocks = cached
            applySort()
        }

        startPricePolling()

        // App 从后台回到前台时立刻刷新价格
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshLivePrices()
            self?.updatePositionPrices()
        }

        Task { [weak self] in
            await self?.loadData()
            await self?.updatePrices()
            await self?.loadFinancialUpdates()
            // updatePrices 完成后立刻拉一次实时价格，不用等 timer
            self?.refreshLivePrices()
        }
    }

    func loadFavoriteEntryPrices() {
        if let saved = UserDefaults.standard.dictionary(forKey: favoriteEntryPricesKey) as? [String: Double] {
            favoriteEntryPrices = saved
        }
    }

    func saveFavoriteEntryPrices() {
        UserDefaults.standard.set(favoriteEntryPrices, forKey: favoriteEntryPricesKey)
    }

    func loadFavoriteStockData() {
        if let data = UserDefaults.standard.data(forKey: favoriteStockDataKey),
           let saved = try? JSONDecoder().decode([String: CachedStockData].self, from: data) {
            favoriteStockData = saved
        }
    }

    func saveFavoriteStockData() {
        if let data = try? JSONEncoder().encode(favoriteStockData) {
            UserDefaults.standard.set(data, forKey: favoriteStockDataKey)
        }
    }

    func loadWatchlistStockCache() {
        if let data = UserDefaults.standard.data(forKey: watchlistStockCacheKey),
           let saved = try? JSONDecoder().decode([String: Stock].self, from: data) {
            watchlistStockCache = saved
        }
    }

    func saveWatchlistStockCache() {
        if let data = try? JSONEncoder().encode(watchlistStockCache) {
            UserDefaults.standard.set(data, forKey: watchlistStockCacheKey)
        }
    }

    // 用最新数据更新自选股缓存
    func refreshFavoriteStockData() {
        let allFavoritedCodes = Set(watchlists.flatMap { $0.stockCodes })
        for code in allFavoritedCodes {
            if let stock = allStocksDict[code],
               let price = stock.price {
                favoriteStockData[code] = CachedStockData(name: stock.name, price: price)
                watchlistStockCache[code] = stock
            }
        }
    }

    // 补全不在选股列表中的自选股数据
    func fetchMissingFavorites() async {
        let allFavoritedCodes = Set(watchlists.flatMap { $0.stockCodes })
        let missingCodes = allFavoritedCodes.filter { code in
            !allStocks.contains(where: { $0.code == code })
        }
        guard !missingCodes.isEmpty else { return }

        do {
            let result: BatchStockResponse = try await APIClient.post("/stocks/batch", body: ["codes": Array(missingCodes)], retries: 2, timeout: 15)

            guard result.code == 0, let batchData = result.data else { return }

            // 先在后台准备好所有数据，再一次性在主线程应用
            var newStocks: [Stock] = []
            var newCache: [String: Stock] = [:]
            var newData: [String: CachedStockData] = [:]

            for (code, stock) in batchData {
                let finalStock: Stock
                if stock.code.isEmpty || stock.name.isEmpty {
                    finalStock = Stock(code: code, name: stock.name.isEmpty ? code : stock.name, price: stock.price, change_pct: stock.change_pct)
                } else {
                    finalStock = stock
                }
                newStocks.append(finalStock)
                newCache[code] = finalStock
                let name = finalStock.name.isEmpty ? code : finalStock.name
                let price = finalStock.price ?? favoriteEntryPrices[code] ?? 0
                newData[code] = CachedStockData(name: name, price: price)
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.allStocks.append(contentsOf: newStocks)
                self.watchlistStockCache.merge(newCache) { _, new in new }
                self.favoriteStockData.merge(newData) { _, new in new }
                self.refreshFavoriteStockData()
            }
        } catch {
            print("补全自选股数据失败: \(error)")
        }
    }

    func loadFavoriteDates() {
        if let saved = UserDefaults.standard.dictionary(forKey: favoriteDatesKey) as? [String: TimeInterval] {
            favoriteDates = saved.mapValues { Date(timeIntervalSince1970: $0) }
        }
    }

    func saveFavoriteDates() {
        let timeIntervals = favoriteDates.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(timeIntervals, forKey: favoriteDatesKey)
    }

    // ========== 多自选列表管理 ==========

    var currentWatchlist: Watchlist? {
        watchlists.first(where: { $0.id == selectedWatchlistId }) ?? watchlists.first
    }

    var currentWatchlistCodes: Set<String> {
        Set(currentWatchlist?.stockCodes ?? [])
    }

    func createWatchlist(name: String) {
        let newList = Watchlist(name: name, stockCodes: [])
        watchlists.append(newList)
        selectedWatchlistId = newList.id
    }

    func renameWatchlist(id: String, name: String) {
        if let index = watchlists.firstIndex(where: { $0.id == id }), !name.isEmpty {
            watchlists[index].name = name
            saveWatchlists()
        }
    }

    func deleteWatchlist(id: String) {
        guard watchlists.count > 1 else { return }
        watchlists.removeAll(where: { $0.id == id })
        if selectedWatchlistId == id {
            selectedWatchlistId = watchlists.first?.id ?? ""
        }
        saveWatchlists()
    }

    func selectWatchlist(id: String) {
        selectedWatchlistId = id
    }

    func addStockToWatchlist(watchlistId: String? = nil, code: String) {
        let targetId = watchlistId ?? (selectedWatchlistId.isEmpty ? watchlists.first?.id ?? "" : selectedWatchlistId)
        guard !targetId.isEmpty,
              let index = watchlists.firstIndex(where: { $0.id == targetId }),
              !watchlists[index].stockCodes.contains(code) else { return }
        watchlists[index].stockCodes.insert(code, at: 0)
        saveWatchlists()

        if favoriteDates[code] == nil {
            favoriteDates[code] = Date()
        }
        if let stock = allStocksDict[code],
           let price = stock.price {
            favoriteEntryPrices[code] = price
            favoriteStockData[code] = CachedStockData(name: stock.name, price: price)
            watchlistStockCache[code] = stock
        }
        fetchLivePrice(for: code)
    }

    func removeStockFromWatchlist(watchlistId: String? = nil, code: String) {
        let targetId = watchlistId ?? selectedWatchlistId
        guard !targetId.isEmpty,
              let index = watchlists.firstIndex(where: { $0.id == targetId }) else { return }
        watchlists[index].stockCodes.removeAll(where: { $0 == code })
        saveWatchlists()

        let stillFavorited = watchlists.contains { $0.stockCodes.contains(code) }
        if !stillFavorited {
            watchlistStockCache.removeValue(forKey: code)
            favoriteStockData.removeValue(forKey: code)
            favoriteEntryPrices.removeValue(forKey: code)
            favoriteDates.removeValue(forKey: code)
        }
    }

    // 添加到自选（使用当前选中列表）
    func addToFavorites(_ code: String) {
        addStockToWatchlist(code: code)
    }

    // 添加到自选并缓存完整 Stock 数据
    func addToFavorites(_ stock: Stock) {
        addStockToWatchlist(code: stock.code)
        watchlistStockCache[stock.code] = stock
        if favoriteEntryPrices[stock.code] == nil, let price = stock.price {
            favoriteEntryPrices[stock.code] = price
        }
        favoriteStockData[stock.code] = CachedStockData(name: stock.name, price: stock.price ?? favoriteEntryPrices[stock.code] ?? 0)
        fetchLivePrice(for: stock.code)
    }

    // 从自选移除（从当前选中列表）
    func removeFromFavorites(_ code: String) {
        removeStockFromWatchlist(code: code)
    }

    // 计算加入自选后的涨跌幅
    func calculateFavoriteReturn(_ code: String) -> Double? {
        guard let entryPrice = favoriteEntryPrices[code],
              let currentPrice = latestPrice(for: code),
              entryPrice > 0 else {
            return nil
        }
        return (currentPrice - entryPrice) / entryPrice * 100
    }

    // ========== 模拟交易功能 ==========
    @Published var positions: [String: Position] = [:]
    @Published var trades: [Trade] = []

    @AppStorage("initialCapital") var initialCapital: Double = 100000

    let positionsKey = "virtual_positions"
    let tradesKey = "virtual_trades"

    var cashBalance: Double {
        let bought = trades.filter { $0.isBuy }.reduce(0.0) { $0 + $1.totalAmount }
        let sold = trades.filter { !$0.isBuy }.reduce(0.0) { $0 + $1.totalAmount }
        return initialCapital - bought + sold
    }

    var netWorth: Double {
        totalMarketValue + cashBalance
    }

    var totalReturnAllTime: Double {
        netWorth - initialCapital
    }

    var totalReturnAllTimePct: Double {
        guard initialCapital > 0 else { return 0 }
        return totalReturnAllTime / initialCapital * 100
    }

    func loadPositions() {
        if let data = UserDefaults.standard.data(forKey: positionsKey),
           let saved = try? JSONDecoder().decode([String: Position].self, from: data) {
            positions = saved
        }
    }

    func savePositions() {
        let saved = positions
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(saved) {
                UserDefaults.standard.set(data, forKey: self.positionsKey)
            }
        }
    }

    func loadTrades() {
        if let data = UserDefaults.standard.data(forKey: tradesKey),
           let saved = try? JSONDecoder().decode([Trade].self, from: data) {
            trades = saved
        }
    }

    func saveTrades() {
        let saved = trades
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(saved) {
                UserDefaults.standard.set(data, forKey: self.tradesKey)
            }
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
            position.currentPrice = price
            positions[code] = position
        } else {
            // 新建持仓
            positions[code] = Position(
                code: code,
                name: name,
                quantity: quantity,
                avgCost: price,
                firstBuyDate: Date(),
                currentPrice: price
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
        position.currentPrice = price
        if position.quantity == 0 {
            positions.removeValue(forKey: code)
        } else {
            positions[code] = position
        }

        saveTrades()
        savePositions()
        return true
    }

    // 删除指定交易记录
    func deleteTrades(ids: Set<String>) {
        trades.removeAll { ids.contains($0.id) }
        saveTrades()
    }

    // 获取持仓
    func getPosition(_ code: String) -> Position? {
        positions[code]
    }

    // 获取所有持仓列表（按实时收益率排序）
    var positionList: [Position] {
        Array(positions.values).sorted { a, b in
            let p0 = latestPrice(for: a.code) ?? a.currentPrice
            let p1 = latestPrice(for: b.code) ?? b.currentPrice
            return a.realTimeReturnPct(p0) > b.realTimeReturnPct(p1)
        }
    }

    // 获取任意股票的最新价格（livePrices → allStocksDict → watchlistStockCache → favoriteStockData → favoriteEntryPrices）
    func latestPrice(for code: String) -> Double? {
        if let live = livePrices[code] {
            return live.price
        }
        if let price = allStocksDict[code]?.price {
            return price
        }
        if let price = watchlistStockCache[code]?.price {
            return price
        }
        if let price = favoriteStockData[code]?.price {
            return price
        }
        return favoriteEntryPrices[code]
    }

    // 获取任意股票的最新涨跌幅
    func latestChangePct(for code: String) -> Double? {
        if let live = livePrices[code], let pct = live.changePct {
            return pct
        }
        if let pct = allStocksDict[code]?.change_pct {
            return pct
        }
        return watchlistStockCache[code]?.change_pct
    }

    // 持仓总市值
    var totalMarketValue: Double {
        positions.values.reduce(0) { acc, pos in
            let price = latestPrice(for: pos.code) ?? pos.currentPrice
            return acc + price * Double(pos.quantity)
        }
    }

    // 持仓盈亏（未实现盈亏）
    var totalPositionReturn: Double {
        totalReturn
    }

    // 当日盈亏
    var totalDailyReturn: Double {
        positions.values.reduce(0) { acc, pos in
            let price = latestPrice(for: pos.code) ?? pos.currentPrice
            guard price > 0, pos.quantity > 0 else { return acc }
            let pct = latestChangePct(for: pos.code) ?? 0
            guard pct != -100 else { return acc }
            // 今日盈亏 = 昨日市值 * 涨跌幅 = price*quantity / (1+pct/100) * pct/100
            let yesterdayPrice = price / (1 + pct / 100)
            return acc + (price - yesterdayPrice) * Double(pos.quantity)
        }
    }

    // 更新持仓的当前价格（用于计算盈亏）
    func updatePositionPrices() {
        // 先用本地缓存更新（批量构建，一次性赋值减少 @Published 触发次数）
        var updated = positions
        for (code, position) in updated {
            if let price = latestPrice(for: code), price > 0 {
                var pos = position
                pos.currentPrice = price
                updated[code] = pos
            }
        }
        positions = updated
        // 持久化移到后台，避免主线程卡顿
        let saved = updated
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(saved) {
                UserDefaults.standard.set(data, forKey: self.positionsKey)
            }
        }
        // 异步从服务端补全所有持仓价格（stock_kline兜底）
        Task { await refreshPositionPricesFromServer() }
    }

    // 从服务端获取持仓股票的最新价格（stock_kline表兜底）
    func refreshPositionPricesFromServer() async {
        let codesToFetch = Array(positions.keys)
        guard !codesToFetch.isEmpty else { return }

        do {
            let result: PriceResponse = try await APIClient.post("/stocks/prices", body: ["codes": codesToFetch], retries: 1, timeout: 10)
            guard result.code == 0, let data = result.data else { return }

            var updates: [(String, Double)] = []
            for (code, priceInfo) in data {
                if let price = priceInfo.price, price > 0, positions[code] != nil {
                    updates.append((code, price))
                }
            }

            if !updates.isEmpty {
                let saved = await MainActor.run { [weak self] in
                    guard let self else { return [String: Position]() }
                    for (code, price) in updates {
                        self.positions[code]?.currentPrice = price
                    }
                    return self.positions
                }
                // 持久化移到后台
                DispatchQueue.global(qos: .utility).async {
                    if let data = try? JSONEncoder().encode(saved) {
                        UserDefaults.standard.set(data, forKey: self.positionsKey)
                    }
                }
            }
        } catch {
            print("刷新持仓价格失败: \(error)")
        }
    }

    // 持仓总成本
    var totalCost: Double {
        positions.values.reduce(0) { $0 + $1.totalCost }
    }

    // 总盈亏（实时价格计算）
    var totalReturn: Double {
        positions.values.reduce(0) { acc, pos in
            let price = latestPrice(for: pos.code) ?? pos.currentPrice
            return acc + pos.realTimePositionReturn(price)
        }
    }

    // 总收益率（实时价格计算）
    var totalReturnPct: Double {
        let totalCost = positions.values.reduce(0.0) { $0 + $1.totalCost }
        guard totalCost > 0 else { return 0 }
        return totalReturn / totalCost * 100
    }

    func loadStoredFilters() {
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

    func saveFilters() {
        UserDefaults.standard.set(Array(activeFilters), forKey: filtersKey)
        UserDefaults.standard.set(Date(), forKey: filtersLastAppliedKey)
        UserDefaults.standard.set(Date(), forKey: sessionStartKey)
        print("保存筛选条件: \(Array(activeFilters))")
    }

    func loadWatchlists() {
        // 尝试加载新的 watchlists 格式
        if let data = UserDefaults.standard.data(forKey: watchlistsKey),
           let saved = try? JSONDecoder().decode([Watchlist].self, from: data),
           !saved.isEmpty {
            watchlists = saved
            let savedId = UserDefaults.standard.string(forKey: selectedWatchlistIdKey) ?? ""
            if watchlists.contains(where: { $0.id == savedId }) {
                selectedWatchlistId = savedId
            } else {
                selectedWatchlistId = watchlists.first?.id ?? ""
            }
            return
        }

        // 迁移旧 favorites 数据
        let oldFavoritesKey = "favorited_stocks"
        if let savedFavorites = UserDefaults.standard.array(forKey: oldFavoritesKey) as? [String],
           !savedFavorites.isEmpty {
            let defaultList = Watchlist(name: "我的自选", stockCodes: savedFavorites)
            watchlists = [defaultList]
            selectedWatchlistId = defaultList.id
            saveWatchlists()
            // 清除旧 key
            UserDefaults.standard.removeObject(forKey: oldFavoritesKey)
            return
        }

        // 无数据，创建默认空列表
        let defaultList = Watchlist(name: "我的自选", stockCodes: [])
        watchlists = [defaultList]
        selectedWatchlistId = defaultList.id
    }

    func saveWatchlists() {
        if let data = try? JSONEncoder().encode(watchlists) {
            UserDefaults.standard.set(data, forKey: watchlistsKey)
        }
    }

    // 更新实时价格
    func updatePrices() async {
        let _: EmptyResponse? = try? await APIClient.post("/update_prices", body: [:], retries: 1, timeout: 15)
    }

    func startPricePolling() {
        priceTimer?.invalidate()
        priceTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.pollLivePrices()
        }
    }

    func stopPricePolling() {
        priceTimer?.invalidate()
        priceTimer = nil
    }

    private func isTradingHour() -> Bool {
        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        guard (2...6).contains(weekday) else { return false }
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let totalMinutes = hour * 60 + minute
        // A股交易时段: 9:30-11:30, 13:00-15:00
        let morningStart = 9 * 60 + 30
        let morningEnd = 11 * 60 + 30
        let afternoonStart = 13 * 60
        let afternoonEnd = 15 * 60
        return (totalMinutes >= morningStart && totalMinutes < morningEnd) ||
               (totalMinutes >= afternoonStart && totalMinutes < afternoonEnd)
    }

    private func pollLivePrices(force: Bool = false) {
        guard !isPollingPrices else { return }
        guard force || isTradingHour() else { return }
        isPollingPrices = true

        var codes = Set<String>()
        for stock in allStocks { codes.insert(stock.code) }
        for list in watchlists { codes.formUnion(list.stockCodes) }
        for code in watchlistStockCache.keys { codes.insert(code) }
        for code in positions.keys { codes.insert(code) }

        guard !codes.isEmpty else {
            isPollingPrices = false
            return
        }

        // 用户关注的代码优先（自选 + 持仓），第一批就能刷新UI
        let priorityCodes = Set(watchlists.flatMap { $0.stockCodes }).union(positions.keys)
        let allCodes = Array(priorityCodes) + Array(codes.subtracting(priorityCodes))
        let batchSize = 80
        let batchCount = (allCodes.count + batchSize - 1) / batchSize
        print("[轮询] 获取 \(allCodes.count) 只价格(分\(batchCount)批, 优先\(priorityCodes.count)只)")
        pollingGeneration += 1
        let gen = pollingGeneration
        pollingTask = Task { [weak self] in
            defer {
                if self?.pollingGeneration == gen {
                    self?.isPollingPrices = false
                }
            }

            for i in stride(from: 0, to: allCodes.count, by: batchSize) {
                if Task.isCancelled { return }
                let batch = Array(allCodes[i..<min(i + batchSize, allCodes.count)])
                do {
                    let result: PriceResponse = try await APIClient.post("/stocks/prices", body: ["codes": batch], retries: 0, timeout: 10)
                    if result.code == 0, let data = result.data {
                        var batchUpdate: [String: LivePrice] = [:]
                        for (code, info) in data {
                            if let price = info.price {
                                batchUpdate[code] = LivePrice(price: price, changePct: info.change_pct)
                            }
                        }
                        // 每批完成立刻更新，不等剩余批次
                        if !batchUpdate.isEmpty {
                            await MainActor.run { [weak self] in
                                self?.livePrices.merge(batchUpdate) { _, new in new }
                            }
                        }
                    }
                } catch {
                    print("[轮询] 批次失败: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 下拉刷新时立即触发一次价格轮询
    func refreshLivePrices() {
        pollingTask?.cancel()
        isPollingPrices = false
        pollLivePrices(force: true)
    }

    /// 立即获取单只股票的实时价格
    private func fetchLivePrice(for code: String) {
        Task { [weak self] in
            do {
                let result: PriceResponse = try await APIClient.post("/stocks/prices", body: ["codes": [code]], retries: 0, timeout: 10)
                guard result.code == 0, let data = result.data, let info = data[code], let price = info.price else { return }
                await MainActor.run { [weak self] in
                    self?.livePrices[code] = LivePrice(price: price, changePct: info.change_pct)
                }
            } catch {
                // 静默失败
            }
        }
    }

    func loadCachedStocks() -> [Stock]? {
        let key = "cached_stocks_\(selectionType == .newRule ? "new_rule" : "standard")"
        guard let data = UserDefaults.standard.data(forKey: key),
              let stocks = try? JSONDecoder().decode([Stock].self, from: data),
              !stocks.isEmpty else { return nil }
        return stocks
    }

    func loadCachedStocks(for type: SelectionType) -> [Stock]? {
        let key = "cached_stocks_\(type == .newRule ? "new_rule" : "standard")"
        guard let data = UserDefaults.standard.data(forKey: key),
              let stocks = try? JSONDecoder().decode([Stock].self, from: data),
              !stocks.isEmpty else { return nil }
        return stocks
    }

    /// 从后台线程运行（init 的 Task 不继承 @MainActor），避免阻塞主线程
    private var isLoadingData = false  // 防止并发 loadData 调用

    func loadData() async {
        guard !isLoadingData else { return }
        isLoadingData = true
        defer { isLoadingData = false }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let selType = selectionType
            if selType == .newRule {
                // 已通过自定义筛选 → 直接显示筛选结果，不再调接口
                let alreadyScreened = await MainActor.run { self.isCustomScreening && !self.screeningResults.isEmpty }
                if alreadyScreened {
                    await MainActor.run { [weak self] in
                        self?.allStocks = self?.screeningResults ?? []
                        self?.stocks = self?.screeningResults ?? []
                        self?.applySort()
                        self?.isLoading = false
                        self?.errorMessage = nil
                    }
                    await fetchMissingFavorites()
                    return
                }
                // 否则调 /screen 全条件开启
                let allConditions: [String: Bool] = [
                    "listed_over_180d": true, "not_st": true,
                    "revenue_over_5yi": true, "revenue_yoy_over_25": true,
                    "rd_ratio_over_10": true, "rev_cagr_over_30": false,
                    "debt_ratio_under_60": true, "operating_cashflow_positive": true,
                    "inst_ownership_over_5": false, "emerging_concept": true
                ]
                let screenResult: ScreeningResponse = try await APIClient.post("/screen", body: ["conditions": allConditions])
                if screenResult.code == 0, let data = screenResult.data {
                    await MainActor.run { [weak self] in
                        self?.allStocks = data
                        self?.stocks = data
                        self?.refreshFavoriteStockData()
                        self?.applySort()
                        self?.errorMessage = nil
                    }
                    if let stocksCopy = await MainActor.run(body: { [weak self] in self?.allStocks }) {
                        Task.detached { [stocksCopy] in
                            if let data = try? JSONEncoder().encode(stocksCopy) {
                                UserDefaults.standard.set(data, forKey: "cached_stocks_new_rule")
                                UserDefaults.standard.set(Date(), forKey: "cached_stocks_date")
                            }
                        }
                    }
                    await fetchMissingFavorites()
                } else {
                    await MainActor.run { [weak self] in
                        self?.errorMessage = "API错误: \(screenResult.message ?? "未知错误")"
                    }
                }
            } else {
                let stockResponse: StockResponse = try await APIClient.get("/stocks", queryItems: [URLQueryItem(name: "page_size", value: "500"), URLQueryItem(name: "type", value: "standard")], retries: 2)
                if stockResponse.code == 0, let data = stockResponse.data {
                    await MainActor.run { [weak self] in
                        self?.allStocks = data
                        self?.stocks = data
                        self?.refreshFavoriteStockData()
                        self?.applySort()
                        self?.errorMessage = nil
                    }
                    if let stocksCopy = await MainActor.run(body: { [weak self] in self?.allStocks }) {
                        Task.detached { [stocksCopy] in
                            if let data = try? JSONEncoder().encode(stocksCopy) {
                                UserDefaults.standard.set(data, forKey: "cached_stocks_standard")
                                UserDefaults.standard.set(Date(), forKey: "cached_stocks_date")
                            }
                        }
                    }
                    await fetchMissingFavorites()
                } else {
                    await MainActor.run { [weak self] in
                        self?.errorMessage = "API错误: \(stockResponse.message ?? "未知错误")"
                    }
                }
            }
        } catch let error as APIClient.APIError {
            // 网络不可用时使用缓存
            if case .networkError = error, let cached = loadCachedStocks() {
                await MainActor.run { [weak self] in
                    self?.allStocks = cached
                    self?.stocks = cached
                    self?.applySort()
                    self?.errorMessage = "无法连接服务器，显示缓存数据"
                }
            } else {
                await MainActor.run { [weak self] in
                    self?.errorMessage = error.errorDescription
                }
            }
        } catch {
            if let cached = loadCachedStocks() {
                await MainActor.run { [weak self] in
                    self?.allStocks = cached
                    self?.stocks = cached
                    self?.applySort()
                    self?.errorMessage = "无法连接服务器，显示缓存数据"
                }
            } else {
                await MainActor.run { [weak self] in
                    self?.errorMessage = "未知错误: \(error.localizedDescription)"
                }
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }

    // 调用后端API应用筛选
    func applyServerFilters(_ filters: Set<String>) async {
        guard !filters.isEmpty else {
            await MainActor.run { [weak self] in
                self?.stocks = self?.allStocks ?? []
                self?.applySort()
            }
            return
        }

        do {
            let result: StockResponse = try await APIClient.post("/filter", body: ["filters": Array(filters)])
            if result.code == 0 {
                await MainActor.run { [weak self] in
                    self?.stocks = result.data ?? []
                    self?.applySort()
                }
            }
        } catch let error as APIClient.APIError {
            print("筛选失败: \(error.errorDescription ?? "")")
        } catch {
            print("筛选失败: \(error)")
        }
    }

    // 自定义动态筛选
    func applyCustomScreening(_ conditions: [String: Bool]) async {
        await MainActor.run { isLoading = true }

        do {
            let result: ScreeningResponse = try await APIClient.post("/screen", body: ["conditions": conditions])
            if result.code == 0 {
                let results = result.data ?? []
                await MainActor.run { [weak self] in
                    self?.screeningResults = results
                    self?.screeningTotal = result.total ?? 0
                    self?.screeningStats = result.stats
                    self?.stocks = results
                    self?.allStocks = results
                    self?.isCustomScreening = true
                    self?.applySort()
                }
                // 同步写入 new_rule 缓存，保持两个 Tab 一致
                if let data = try? JSONEncoder().encode(results) {
                    UserDefaults.standard.set(data, forKey: "cached_stocks_new_rule")
                    UserDefaults.standard.set(Date(), forKey: "cached_stocks_date")
                }
            }
        } catch let error as APIClient.APIError {
            print("自定义筛选失败: \(error.errorDescription ?? "")")
        } catch {
            print("自定义筛选失败: \(error)")
        }

        await MainActor.run { isLoading = false }
    }

    func clearCustomScreening() {
        isCustomScreening = false
        screeningResults = []
        screeningStats = nil
        screeningTotal = 0
        stocks = allStocks
        applySort()
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
        await MainActor.run {
            isLoadingFinancialUpdates = true
        }

        do {
            let result: FinancialUpdatesResponse = try await APIClient.get("/financial_updates", retries: 2)
            if result.code == 0, let data = result.data {
                await MainActor.run { [weak self] in
                    self?.financialUpdateStocks = data.stocks ?? []
                }
            }
        } catch let error as APIClient.APIError {
            print("财务更新加载失败: \(error.errorDescription ?? "")")
        } catch {
            print("财务更新加载失败: \(error)")
        }

        await MainActor.run {
            isLoadingFinancialUpdates = false
        }
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
        // 预计算缓存：当 stocks 数量变化时刷新（新数据加载时）
        if scoreCache.count != stocks.count {
            precomputeDerivedData()
        }
        // 用当前搜索文本过滤（如果有），然后排序 — 一次完成，避免 double-sort
        let baseList = searchFilteredList()
        let sorted = baseList.sorted { stock1, stock2 in
            let value1 = sortValue(for: stock1)
            let value2 = sortValue(for: stock2)
            return sortAscending ? value1 < value2 : value1 > value2
        }
        filteredStocks = sorted
    }

    private func searchFilteredList() -> [Stock] {
        guard !searchText.isEmpty else { return stocks }
        let query = searchText.lowercased()
        return stocks.filter { stock in
            stock.code.lowercased().contains(query) ||
            stock.name.lowercased().contains(query) ||
            (pinyinCache[stock.code] ?? Self.pinyinInitials(stock.name)).contains(query)
        }
    }

    private func applySearch() {
        // applySort() 内部会调用 searchFilteredList()，避免双重过滤
        applySort()
    }

    /// 获取中文名称的拼音首字母，如 "京东方A" → "jdfa"
    static func pinyinInitials(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return String(mutable)
            .split(separator: " ")
            .compactMap { $0.first }
            .map { String($0).lowercased() }
            .joined()
    }

    private func sortValue(for stock: Stock, option: SortOption? = nil) -> Double {
        switch option ?? sortOption {
        case .added:
            return 0
        case .position:
            return stock.price_position ?? 1.0
        case .pe:
            return stock.pe_ttm ?? 0
        case .score:
            return scoreCache[stock.code] ?? calculateScore(stock)
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
            // 当日涨跌幅（实时价格优先）
            return latestChangePct(for: stock.code) ?? stock.change_pct ?? 0
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

    /// 计算退市风险等级（缓存至 riskCache，避免 StockCard 每行重复计算）
    func computeRiskLevel(_ stock: Stock) -> (level: String, detail: String) {
        let code = stock.code
        let profitNegative: Bool = {
            guard let yoy = stock.net_profit_yoy else { return false }
            let clean = yoy.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")
            guard let value = Double(clean) else { return false }
            return value < 0
        }()
        let revenueYuan: Double? = {
            guard let rev = stock.revenue, !rev.isEmpty else { return nil }
            let numStr = rev.replacingOccurrences(of: "亿", with: "").replacingOccurrences(of: "万", with: "").replacingOccurrences(of: "元", with: "")
            guard let num = Double(numStr) else { return nil }
            if rev.contains("万") { return num * 10000 }
            if rev.contains("亿") { return num * 100000000 }
            return num
        }()
        let revenueThreshold: Double = code.hasPrefix("68") ? 50_000_000 : (code.hasPrefix("30") ? 100_000_000 : 300_000_000)
        let bvNegative = (stock.book_value_per_share ?? 0) < 0
        let priceVal = stock.price ?? 0
        let fraudRisk = stock.financial_fraud_risk ?? 0
        let embezzlementRisk = stock.fund_embezzlement_risk ?? 0
        let otherReceivablesRatio = stock.other_receivables_ratio ?? 0

        if fraudRisk >= 2 { return ("*ST", "财务造假处罚") }
        if profitNegative, let rev = revenueYuan, rev < revenueThreshold { return ("*ST", "净利负+营收不达标") }
        if bvNegative { return ("*ST", "净资产为负") }
        if fraudRisk >= 1 { return ("警示", "有财务违规处罚") }
        if embezzlementRisk >= 1 { return ("警示", "资金占用风险") }
        if otherReceivablesRatio > 30 { return ("警示", "其他应收款占比>30%") }
        if profitNegative && priceVal < 1.0 && priceVal > 0 { return ("警示", "净利负+股价<1元") }
        if priceVal < 1.0 && priceVal > 0 { return ("警示", "股价<1元") }
        if profitNegative { return ("警示", "净利润为负") }
        if let roeStr = stock.roe, let roeVal = Double(roeStr.replacingOccurrences(of: "%", with: "")), roeVal < 0 { return ("警示", "ROE为负") }
        if let divCount = stock.dividend_count, divCount == 0 { return ("警示", "从未分红") }
        return ("安全", "")
    }

    /// 自选股列表（已优化为 O(1) 字典查找）
    func isFavorited(_ code: String) -> Bool {
        // 检查所有列表，不只是当前选中列表
        return watchlists.contains(where: { $0.stockCodes.contains(code) })
    }

    func toggleFavorite(_ stock: Stock) {
        if isFavorited(stock.code) {
            // 从所有列表移除
            for i in watchlists.indices {
                watchlists[i].stockCodes.removeAll(where: { $0 == stock.code })
            }
            saveWatchlists()
        } else {
            addToFavorites(stock.code)
        }
    }

    var favoritedStocks: [Stock] {
        let codes = currentWatchlist?.stockCodes ?? []
        var seen = Set<String>()
        return codes.compactMap { code in
            guard seen.insert(code).inserted else { return nil }
            if let stock = allStocksDict[code] {
                if let live = livePrices[code] {
                    var copy = stock
                    copy.price = live.price
                    if let pct = live.changePct { copy.change_pct = pct }
                    return copy
                }
                return stock
            }
            if var cached = watchlistStockCache[code] {
                if let live = livePrices[code] {
                    cached.price = live.price
                    if let pct = live.changePct { cached.change_pct = pct }
                    return cached
                }
                return cached
            }
            if let cached = favoriteStockData[code] {
                let price = livePrices[code]?.price ?? cached.price
                let changePct = livePrices[code]?.changePct
                return Stock(code: code, name: cached.name, price: price, change_pct: changePct)
            }
            let price = livePrices[code]?.price ?? favoriteEntryPrices[code]
            let changePct = livePrices[code]?.changePct
            return Stock(code: code, name: "未知", price: price, change_pct: changePct)
        }
    }

    var sortedFavoritedStocks: [Stock] {
        let stocks = favoritedStocks
        if watchlistSortOption == .added {
            return watchlistSortAscending ? stocks.reversed() : stocks
        }
        let opt = watchlistSortOption
        return stocks.sorted { s1, s2 in
            let v1 = sortValue(for: s1, option: opt)
            let v2 = sortValue(for: s2, option: opt)
            return watchlistSortAscending ? v1 < v2 : v1 > v2
        }
    }
}

