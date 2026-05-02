import SwiftUI
import Charts
import UIKit

struct StockListView: View {
    @EnvironmentObject var stockViewModel: StockViewModel
    @State private var selectedStockCode: String = ""
    @State private var showDetailPage = false

    private var resolvedStockIndex: Int {
        stockViewModel.filteredStocks.firstIndex(where: { $0.code == selectedStockCode }) ?? 0
    }

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
                            showDetailPage = true
                        } label: {
                            StockCard(stock: stock, sortOption: stockViewModel.sortOption)
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
            let idx = resolvedStockIndex
            if idx < stockViewModel.filteredStocks.count {
                StockDetailPageView(
                    currentIndex: idx,
                    allStocks: stockViewModel.filteredStocks,
                    currentPage: .constant(idx)
                )
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
    @EnvironmentObject var stockViewModel: StockViewModel

    init(stock: Stock, sortOption: SortOption = .position) {
        self.stock = stock
        self.sortOption = sortOption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 第一行：板块/名称代码 + 价格 + 当日涨跌 + 收藏
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let sector = stock.sector, !sector.isEmpty {
                        Text(sector)
                            .font(.headline)
                            .foregroundColor(.white)
                    } else {
                        Text(stock.name)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(stock.code)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    if let sector = stock.sector, !sector.isEmpty {
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
                            stockViewModel.toggleFavorite(stock)
                        }
                    } label: {
                        Image(systemName: stockViewModel.isFavorited(stock.code) ? "star.fill" : "star")
                            .foregroundColor(stockViewModel.isFavorited(stock.code) ? Color(hex: "FFC107") : .gray)
                            .font(.title3)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
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

    // 退市风险预警（根据不同市场差异化规则）
    // 主板：净利润为负+营收<3亿 或 净资产为负 → *ST
    // 创业板：净利润为负+营收<1亿 或 净资产为负 → *ST
    // 科创板：净利润为负+营收<5000万 或 净资产为负 → *ST
    func riskLevel() -> (level: String, detail: String) {
        // 检查各项风险指标
        let roeNegative = checkROE()
        let profitNegative = checkProfit()
        let priceLow = checkPrice()

        // *ST条件：净利润同比下降超过50%
        if profitNegative {
            return ("*ST", "退市风险")
        }

        // 警示条件：ROE为负
        if roeNegative {
            return ("警示", "ROE为负")
        }

        // 低股��警示：股价<1元
        if priceLow {
            return ("警示", "低价")
        }

        return ("安全", "")
    }

    // 检查ROE是否为负
    private func checkROE() -> Bool {
        guard let roe = stock.roe else { return false }
        let roeClean = roe.replacingOccurrences(of: "%", with: "")
        guard let value = Double(roeClean) else { return false }
        return value < 0
    }

    // 检查净利润是否为负或同比下降
    private func checkProfit() -> Bool {
        guard let yoy = stock.net_profit_yoy else { return false }
        let yoyClean = yoy.replacingOccurrences(of: "%", with: "")
        guard let value = Double(yoyClean) else { return false }
        return value < -50  // 净利润同比下降超过50%
    }

    // 检查股价是否过低
    private func checkPrice() -> Bool {
        guard let price = stock.price else { return false }
        return price < 1.0  // 连续20交易日<1元直接退市
    }

    // 检查每股净资产是否为负（破净风险）
    private func checkNAV() -> Bool {
        guard let bvps = stock.book_value_per_share,
              let val = Double(bvps) else { return false }
        return val < 0
    }

    // 详细退市风险分析（用于详情页）
    func detailedRiskAnalysis() -> [(rule: String, status: String, detail: String)] {
        var results: [(rule: String, status: String, detail: String)] = []
        let code = stock.code
        let isMainBoard = code.hasPrefix("60") || code.hasPrefix("00")
        let isGEM = code.hasPrefix("30")
        let isSTAR = code.hasPrefix("68")

        // ===== 财务类规则 =====

        // 1. 净利润+营收组合指标
        let revenueThreshold = isSTAR ? "5000万" : (isGEM ? "1亿" : "3亿")
        let profitStatus: String
        let profitDetail: String
        if let yoy = stock.net_profit_yoy {
            let yoyClean = yoy.replacingOccurrences(of: "%", with: "")
            if let yoyVal = Double(yoyClean), yoyVal < 0 {
                profitStatus = "警示"
                profitDetail = "净利润同比下降\(Int(yoyVal))%，需结合营收判断"
            } else if let yoyVal = Double(yoyClean), yoyVal >= 0 {
                profitStatus = "安全"
                profitDetail = "净利润同比增长\(Int(yoyVal))%"
            } else {
                profitStatus = "未知"
                profitDetail = "缺少净利润数据"
            }
        } else {
            profitStatus = "未知"
            profitDetail = "缺少净利润数据"
        }
        results.append(("净利润+营收(\(revenueThreshold))", profitStatus, profitDetail))

        // 2. 净资产
        results.append(("净资产为负", "未知", "缺少每股净资产数据"))

        // 3. ROE
        let roeStatus: String
        let roeDetail: String
        if let roe = stock.roe {
            let roeClean = roe.replacingOccurrences(of: "%", with: "")
            if let roeVal = Double(roeClean), roeVal < 0 {
                roeStatus = "警示"
                roeDetail = "ROE为\(roe)%，亏损"
            } else if let roeVal = Double(roeClean), roeVal >= 0 {
                roeStatus = "安全"
                roeDetail = "ROE为\(roe)%"
            } else {
                roeStatus = "未知"
                roeDetail = "缺少ROE数据"
            }
        } else {
            roeStatus = "未知"
            roeDetail = "缺少ROE数据"
        }
        results.append(("ROE", roeStatus, roeDetail))

        // 4. 审计意见
        results.append(("审计报告非标", "未知", "需审计报告数据"))

        // 5. 分红不达标
        results.append(("分红不达标", "未知", "需分红数据"))

        // ===== 交易类规则 =====

        // 6. 股价<1元
        let priceStatus: String
        let priceDetail: String
        if let price = stock.price, price < 1.0 {
            priceStatus = "危险"
            priceDetail = "股价\(String(format: "%.2f", price))元，连续20日<1元直接退市"
        } else if let price = stock.price, price < 2.0 {
            priceStatus = "警示"
            priceDetail = "股价\(String(format: "%.2f", price))元，接近退市红线"
        } else if let price = stock.price {
            priceStatus = "安全"
            priceDetail = "股价\(String(format: "%.2f", price))元"
        } else {
            priceStatus = "未知"
            priceDetail = "缺少股价数据"
        }
        results.append(("股价<1元", priceStatus, priceDetail))

        // 7. 市值退市
        results.append(("市值<5亿", "未知", "需市值数据"))

        // ===== 规范类规则 =====

        // 8. 资金占用
        results.append(("资金占用", "未知", "需资金占用数据"))

        // 9. 内控失效
        results.append(("内控失效", "未知", "需内控审计数据"))

        // ===== 重大违法类 =====

        // 10. 财务造假
        results.append(("财务造假", "未知", "需调查确认"))

        return results
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
