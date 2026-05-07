import SwiftUI
import Charts
import UIKit

struct StockListView: View {
    @EnvironmentObject var stockViewModel: StockViewModel
    @State private var selectedStockCode: String = ""
    @State private var selectedStockIndex: Int = 0
    @State private var showDetailPage = false
    @State private var showWatchlistPicker = false
    @State private var pendingFavoriteStock: Stock? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let error = stockViewModel.errorMessage {
                Text("错误: \(error)")
                    .foregroundColor(.red)
                    .padding()
            }

            if stockViewModel.stocks.isEmpty && !stockViewModel.isLoading {
                Text("暂无数据")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 排序选项栏
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            SortButton(
                                title: option.rawValue,
                                isSelected: stockViewModel.sortOption == option,
                                isAscending: stockViewModel.sortOption == option ? stockViewModel.sortAscending : nil
                            ) {
                                stockViewModel.toggleSort(option)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(hex: "1E1E1E"))

                // 搜索栏
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("搜索股票代码或名称", text: $stockViewModel.searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.white)
                    if !stockViewModel.searchText.isEmpty {
                        Button {
                            stockViewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(10)
                .background(Color(hex: "2C2C2C"))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // 股票列表
                List {
                    ForEach(Array(stockViewModel.filteredStocks.enumerated()), id: \.element.code) { index, stock in
                        Button {
                            selectedStockCode = stock.code
                            selectedStockIndex = index
                            showDetailPage = true
                        } label: {
                            StockCard(stock: stock, sortOption: stockViewModel.sortOption, showWatchlistPicker: $showWatchlistPicker, pendingFavoriteStock: $pendingFavoriteStock)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .listRowBackground(Color(hex: "1E1E1E"))
                    }
                }
                .listStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
            }
        }
        .background(Color(hex: "121212"))
        .navigationTitle(stockViewModel.activeFilters.isEmpty
            ? "智能选股 (\(stockViewModel.filteredStocks.count))"
            : "筛选结果 (\(stockViewModel.filteredStocks.count))")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await stockViewModel.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .refreshable {
            await stockViewModel.refresh()
        }
        .navigationDestination(isPresented: $showDetailPage) {
            if selectedStockIndex < stockViewModel.filteredStocks.count {
                StockDetailPageView(
                    currentIndex: selectedStockIndex,
                    allStocks: stockViewModel.filteredStocks,
                    currentPage: $selectedStockIndex
                )
            }
        }
        .confirmationDialog("添加到自选列表", isPresented: $showWatchlistPicker, titleVisibility: .visible) {
            ForEach(stockViewModel.watchlists) { list in
                Button(list.name) {
                    if let stock = pendingFavoriteStock {
                        stockViewModel.addStockToWatchlist(watchlistId: list.id, code: stock.code)
                        pendingFavoriteStock = nil
                    }
                }
            }
            Button("取消", role: .cancel) {
                pendingFavoriteStock = nil
            }
        }
    }
}

struct SortButton: View {
    let title: String
    let isSelected: Bool
    let isAscending: Bool?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)

                if isSelected, let ascending = isAscending {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color(hex: "1E88E5") : Color(hex: "2C2C2C"))
            .foregroundColor(isSelected ? .white : .gray)
            .cornerRadius(20)
        }
    }
}

struct StockCard: View {
    let stock: Stock
    var sortOption: SortOption = .position
    @Binding var showWatchlistPicker: Bool
    @Binding var pendingFavoriteStock: Stock?
    @EnvironmentObject var stockViewModel: StockViewModel

    init(stock: Stock, sortOption: SortOption = .position, showWatchlistPicker: Binding<Bool> = .constant(false), pendingFavoriteStock: Binding<Stock?> = .constant(nil)) {
        self.stock = stock
        self.sortOption = sortOption
        self._showWatchlistPicker = showWatchlistPicker
        self._pendingFavoriteStock = pendingFavoriteStock
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 第一行：名称 + 价格 + 当日涨跌 + 收藏
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stock.name)
                        .font(.headline)
                        .foregroundColor(.white)
                    HStack(spacing: 4) {
                        if let sector = stock.sector, !sector.isEmpty {
                            Text(sector)
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        Text(stock.code)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                // 价格 + 当日涨跌（加大间距和字体）
                let changePct = stock.change_pct ?? 0
                HStack(spacing: 6) {
                    Text(String(format: "¥%.2f", stock.price ?? 0))
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(String(format: "%@%.1f%%", changePct >= 0 ? "+" : "", changePct))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(changePct >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))

                VStack(spacing: 4) {
                    // 退市风险警示（星星下面）
                    let risk = riskLevel()
                    if risk.level != "安全" {
                        Text(risk.level)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(risk.level == "*ST" ? Color.red : Color.orange)
                            .cornerRadius(3)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if stockViewModel.isFavorited(stock.code) {
                                stockViewModel.toggleFavorite(stock)
                            } else if stockViewModel.watchlists.count > 1 {
                                pendingFavoriteStock = stock
                                showWatchlistPicker = true
                            } else {
                                stockViewModel.toggleFavorite(stock)
                            }
                        }
                    } label: {
                        Image(systemName: stockViewModel.isFavorited(stock.code) ? "star.fill" : "star")
                            .foregroundColor(stockViewModel.isFavorited(stock.code) ? Color(hex: "FFC107") : .gray)
                            .font(.title3)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // 概念板块标签 + 大涨原因
            if let concepts = stock.concepts, !concepts.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(concepts.prefix(3).enumerated()), id: \.offset) { index, concept in
                        Text(concept)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(hex: conceptColor(index)))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: conceptColor(index)).opacity(0.25))
                            .cornerRadius(4)
                    }
                    if concepts.count > 3 {
                        Text("+\(concepts.count - 3)")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    if let surgeReason = stock.surge_reason, let changePct = stock.change_pct, changePct >= 5.0 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Color(hex: "FF6B00"))
                            Text(surgeReason)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(Color(hex: "FF6B00"))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: "FF6B00").opacity(0.12))
                        .cornerRadius(4)
                    }
                }
            } else if stock.concepts != nil {
                // concepts 为空数组，不显示
                EmptyView()
            }

            // 第二行：指标们
            HStack(spacing: 4) {
                // 5年涨跌
                VStack(spacing: 0) {
                    Text(String(format: "%.0f%%", stock.change_5y ?? 0))
                        .font(.system(size: 11))
                        .foregroundColor((stock.change_5y ?? 0) >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                    Text("5年")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }

                // 位置
                VStack(spacing: 0) {
                    Text(stock.price_position.map { "\(Int($0 * 100))" } ?? "-")
                        .font(.system(size: 11))
                        .foregroundColor(colorForPosition(stock.price_position))
                    Text("位置")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }

                // 评分
                VStack(spacing: 0) {
                    Text(calculateScore())
                        .font(.system(size: 11))
                        .foregroundColor(colorForScore(calculateScore()))
                    Text("评分")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }

                // 筹码
                VStack(spacing: 0) {
                    Text(stock.chip_concentration.map { String(format: "%.0f", $0 * 100) } ?? "-")
                        .font(.system(size: 11))
                        .foregroundColor(colorForChip(stock.chip_concentration))
                    Text("筹码")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }

                // 股东
                VStack(spacing: 0) {
                    Text(shareholderTrendValue())
                        .font(.system(size: 11))
                        .foregroundColor(colorForShareholder(shareholderTrendValue()))
                    Text("股东")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }

                // 背离
                VStack(spacing: 0) {
                    Text(divergenceDots())
                        .font(.system(size: 11))
                        .foregroundColor(colorForDivergence())
                    Text("背")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }

                // 财务数据: ROE
                VStack(spacing: 0) {
                    Text(stock.roe ?? "-")
                        .font(.system(size: 11))
                        .foregroundColor(colorForROE())
                    Text("ROE")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }

                // 财务数据: 净利润同比
                VStack(spacing: 0) {
                    Text(stock.net_profit_yoy ?? "-")
                        .font(.system(size: 10))
                        .foregroundColor(colorForYoy())
                    Text("同比")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }

                // 财务数据: 净利润环比
                VStack(spacing: 0) {
                    Text(stock.net_profit_qoq ?? "-")
                        .font(.system(size: 10))
                        .foregroundColor(colorForQoq())
                    Text("环比")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }

                // 自选收益率（仅在自选股票中显示）
                if let returnPct = stockViewModel.calculateFavoriteReturn(stock.code) {
                    VStack(spacing: 0) {
                        Text(String(format: "%@%.1f%%", returnPct >= 0 ? "+" : "", returnPct))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(returnPct >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                        Text("自选")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(.vertical, 0)
    }

    func colorForROE() -> Color {
        guard let roe = stock.roe else { return Color.gray }
        let roeClean = roe.replacingOccurrences(of: "%", with: "")
        guard let value = Double(roeClean) else { return Color.gray }
        if value > 15 {
            return Color(hex: "FF5252")  // 高ROE=红色
        } else if value > 8 {
            return Color(hex: "FFEB3B")  // 中等=黄色
        }
        return Color.gray
    }

    // 净利润同比颜色
    func colorForYoy() -> Color {
        guard let yoy = stock.net_profit_yoy else { return Color.gray }
        let yoyClean = yoy.replacingOccurrences(of: "%", with: "")
        guard let value = Double(yoyClean) else { return Color.gray }
        if value > 0 {
            return Color(hex: "F44336")  // 增长=红色
        } else if value < 0 {
            return Color(hex: "4CAF50")  // 下降=绿色
        }
        return Color.gray
    }

    // 净利润环比颜色
    func colorForQoq() -> Color {
        guard let qoq = stock.net_profit_qoq else { return Color.gray }
        let qoqClean = qoq.replacingOccurrences(of: "%", with: "")
        guard let value = Double(qoqClean) else { return Color.gray }
        if value > 0 {
            return Color(hex: "F44336")  // 增长=红色
        } else if value < 0 {
            return Color(hex: "4CAF50")  // 下降=绿色
        }
        return Color.gray
    }

    // 退市风险预警（2025年退市新规）
    // *ST: 净利润为负+营收不达标 或 净资产为负
    // 警示: 净利润为负、股价<1元、ROE为负
    func riskLevel() -> (level: String, detail: String) {
        let code = stock.code

        let profitNegative: Bool = {
            guard let yoy = stock.net_profit_yoy else { return false }
            let clean = yoy.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")
            guard let value = Double(clean) else { return false }
            return value < 0
        }()

        // 营收转元（如 "2334.33亿" → 233433000000）
        let revenueYuan: Double? = {
            guard let rev = stock.revenue, !rev.isEmpty else { return nil }
            let numStr = rev.replacingOccurrences(of: "亿", with: "").replacingOccurrences(of: "万", with: "").replacingOccurrences(of: "元", with: "")
            guard let num = Double(numStr) else { return nil }
            if rev.contains("万") { return num * 10000 }
            if rev.contains("亿") { return num * 100000000 }
            return num
        }()

        // 营收门槛（2025新规: 主板3亿/创业板1亿/科创板5000万）
        let revenueThreshold: Double = {
            if code.hasPrefix("68") { return 50_000_000 }
            if code.hasPrefix("30") { return 100_000_000 }
            return 300_000_000
        }()

        let bvNegative: Bool = {
            guard let bv = stock.book_value_per_share else { return false }
            return bv < 0
        }()

        let priceVal = stock.price ?? 0

        // 财务造假风险
        let fraudRisk = stock.financial_fraud_risk ?? 0
        let embezzlementRisk = stock.fund_embezzlement_risk ?? 0
        let otherReceivablesRatio = stock.other_receivables_ratio ?? 0

        // *ST 退市风险警示
        if fraudRisk >= 2 {
            return ("*ST", "财务造假处罚")
        }
        if profitNegative, let rev = revenueYuan, rev < revenueThreshold {
            return ("*ST", "净利负+营收不达标")
        }
        if bvNegative {
            return ("*ST", "净资产为负")
        }

        // 警示
        if fraudRisk >= 1 {
            return ("警示", "有财务违规处罚")
        }
        if embezzlementRisk >= 1 {
            return ("警示", "资金占用风险")
        }
        if otherReceivablesRatio > 30 {
            return ("警示", "其他应收款占比>30%")
        }
        if profitNegative && priceVal < 1.0 && priceVal > 0 {
            return ("警示", "净利负+股价<1元")
        }
        if priceVal < 1.0 && priceVal > 0 {
            return ("警示", "股价<1元")
        }
        if profitNegative {
            return ("警示", "净利润为负")
        }
        if let roeStr = stock.roe, let roeVal = Double(roeStr.replacingOccurrences(of: "%", with: "")), roeVal < 0 {
            return ("警示", "ROE为负")
        }
        if let divCount = stock.dividend_count, divCount == 0 {
            return ("警示", "从未分红")
        }

        return ("安全", "")
    }

    func divergenceDots() -> String {
        guard let div = stock.macd_divergence else { return "" }
        var count = 0
        if div.monthly == true { count += 1 }
        if div.weekly == true { count += 1 }
        if div.daily == true { count += 1 }
        if count == 0 { return "" }
        return String(repeating: "●", count: count)
    }

    func colorForDivergence() -> Color {
        guard let div = stock.macd_divergence else { return .clear }
        if div.monthly == true { return Color(hex: "4CAF50") }
        else if div.weekly == true { return Color(hex: "1E88E5") }
        else if div.daily == true { return Color(hex: "FFC107") }
        else { return .clear }
    }

    func colorForPosition(_ position: Double?) -> Color {
        guard let pos = position else { return .gray }
        if pos < 0.15 { return Color(hex: "4CAF50") }
        else if pos < 0.3 { return Color(hex: "1E88E5") }
        else { return Color(hex: "FFC107") }
    }

    func colorForScore(_ score: String) -> Color {
        guard let value = Double(score), value > 0 else { return .gray }
        if value >= 70 { return Color(hex: "4CAF50") }
        else if value >= 50 { return Color(hex: "1E88E5") }
        else { return Color(hex: "FFC107") }
    }

    func colorForChip(_ chip: Double?) -> Color {
        guard let c = chip else { return .gray }
        if c >= 80 { return Color(hex: "4CAF50") }
        else if c >= 60 { return Color(hex: "1E88E5") }
        else { return Color(hex: "FFC107") }
    }

    func colorForShareholder(_ value: String) -> Color {
        if value.isEmpty || value == "-" { return .gray }
        if value.hasPrefix("+") { return Color(hex: "F44336") }
        if let num = Double(value.replacingOccurrences(of: "%", with: "")), num < -10 { return Color(hex: "4CAF50") }
        return Color(hex: "FFC107")
    }

    func calculateScore() -> String {
        let total = stockViewModel.calculateScore(stock)
        return String(format: "%.0f", total * 100)
    }

    func trendScoreValue() -> Double {
        return stockViewModel.trendScoreValue(stock.trend_analysis)
    }

    func shareholderChangePercent() -> Double {
        return stockViewModel.shareholderChangePercent(stock)
    }

    func shareholderTrendValue() -> String {
        guard let trend = stock.holders_trend, trend.count >= 2 else { return "-" }
        let validTrend = trend.filter { ($0.holders ?? 0) >= 1000 }
        guard validTrend.count >= 2 else { return "-" }
        let oldest = validTrend.first?.holders ?? 0
        let newest = validTrend.last?.holders ?? 0
        guard oldest > 0 else { return "-" }
        let pct = Double(newest - oldest) / Double(oldest) * 100
        if pct > 0 { return "+\(String(format: "%.0f", pct))%" }
        else { return "\(String(format: "%.0f", pct))%" }
    }

    func conceptColor(_ index: Int) -> String {
        let colors = ["4FC3F7", "AED581", "FFB74D", "CE93D8", "EF5350",
                      "26C6DA", "9CCC65", "FFA726", "AB47BC", "42A5F5"]
        return colors[index % colors.count]
    }
}

struct SortMetricView: View {
    let title: String
    let value: String
    let isHighlighted: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 11))
                .fontWeight(isHighlighted ? .bold : .regular)
                .foregroundColor(isHighlighted ? color : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.system(size: 10))
                .foregroundColor(isHighlighted ? color : .gray)
        }
        .frame(width: 44)
        .padding(.vertical, 0)
        .background(isHighlighted ? color.opacity(0.2) : Color.clear)
        .cornerRadius(6)
    }
}
