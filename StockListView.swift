import SwiftUI
import Charts

struct StockListView: View {
    @EnvironmentObject var stockViewModel: StockViewModel
    @State private var selectedStockIndex: Int = 0
    @State private var showDetailPage = false

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
                            selectedStockIndex = index
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
        .navigationTitle("智能选股 (\(stockViewModel.filteredStocks.count))")
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

    // 检查每股净资产（暂无数据字段，暂时返回false）
    private func checkNAV() -> Bool {
        return false
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
        let trendScore = trendScoreValue()
        let pricePct = stock.price_percentile ?? 50
        let valuationScore = (100 - pricePct) / 100.0
        let chipScore = (stock.chip_concentration ?? 50) / 100.0
        let holderPct = shareholderChangePercent()
        let holderScore: Double
        if holderPct < -10 { holderScore = 1.0 }
        else if holderPct < 0 { holderScore = 0.7 }
        else if holderPct < 20 { holderScore = 0.4 }
        else { holderScore = 0.1 }
        var divergenceScore: Double = 0
        if stock.macd_divergence?.monthly == true { divergenceScore += 0.5 }
        if stock.macd_divergence?.weekly == true { divergenceScore += 0.3 }
        if stock.macd_divergence?.daily == true { divergenceScore += 0.2 }
        let total = trendScore * 0.30 + valuationScore * 0.25 + chipScore * 0.20 + holderScore * 0.15 + divergenceScore * 0.10
        return String(format: "%.0f", min(1.0, max(0.0, total)) * 100)
    }

    func trendScoreValue() -> Double {
        guard let t = stock.trend_analysis else { return 0.5 }
        switch t.short {
        case "上涨趋势": return 1.0
        case "震荡": return 0.6
        case "下跌趋势": return 0.2
        default: return 0.5
        }
    }

    func shareholderChangePercent() -> Double {
        guard let trend = stock.holders_trend, trend.count >= 2 else { return 0 }
        let validTrend = trend.filter { ($0.holders ?? 0) >= 1000 }
        guard validTrend.count >= 2 else { return 0 }
        let oldest = validTrend.first?.holders ?? 0
        let newest = validTrend.last?.holders ?? 0
        if oldest > 0 { return Double(newest - oldest) / Double(oldest) * 100 }
        return 0
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

struct StockDetailView: View {
    let stock: Stock
    @State private var selectedQuarterIndex: Int? = nil
    @State private var detailedStock: Stock?
    @State private var isLoading = false
    @State private var selectedKlinePeriod: KlinePeriod = .daily
    @State private var selectedKlineIndex: Int? = nil

    private let baseURL = "http://8.163.91.16:5000/api/v1"

    enum KlinePeriod: String, CaseIterable {
        case daily = "日"
        case weekly = "周"
        case monthly = "月"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 基本信息
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(stock.name)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text(stock.code)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }

                    HStack {
                        Text("当前价格")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                        Text(String(format: "¥%.2f", stock.price ?? 0))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                .padding()
                .background(Color(hex: "1E1E1E"))
                .cornerRadius(12)

                // 股东人数趋势
                if let holders = stock.holders_trend, !holders.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("股东人数趋势")
                            .font(.headline)
                            .foregroundColor(.white)

                        // 股东趋势图 - 带渐变色
                        Chart {
                            ForEach(holders.indices, id: \.self) { index in
                                LineMark(
                                    x: .value("季度", index),
                                    y: .value("股东", holders[index].holders ?? 0)
                                )
                                .foregroundStyle(Color(hex: "1E88E5"))

                                AreaMark(
                                    x: .value("季度", index),
                                    y: .value("股东", holders[index].holders ?? 0)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "1E88E5").opacity(0.3), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                PointMark(
                                    x: .value("季度", index),
                                    y: .value("股东", holders[index].holders ?? 0)
                                )
                                .foregroundStyle(Color(hex: "1E88E5"))
                                .symbolSize(30)
                            }
                        }
                        .frame(height: 160)
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in
                                AxisValueLabel()
                                    .foregroundStyle(Color.gray)
                            }
                        }
                        .chartOverlay { proxy in
                            GeometryReader { geometry in
                                let plotArea = geometry[proxy.plotAreaFrame]
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                let xPos = value.location.x
                                                let cWidth = plotArea.width
                                                let xOff = plotArea.origin.x
                                                if holders.count > 0 {
                                                    let idx = Int(((xPos - xOff) / cWidth) * CGFloat(holders.count))
                                                    let clamped = max(0, min(idx, holders.count - 1))
                                                    selectedQuarterIndex = clamped
                                                }
                                            }
                                            .onEnded { _ in }
                                    )

                                if let index = selectedQuarterIndex, index < holders.count {
                                    let hValue = Double(holders[index].holders ?? 0)
                                    let cWidth = plotArea.width
                                    let xOff = plotArea.origin.x
                                    let xPos = xOff + (CGFloat(index) + 0.5) / CGFloat(holders.count) * cWidth

                                    // 垂直线
                                    Path { path in
                                        path.move(to: CGPoint(x: xPos, y: plotArea.origin.y))
                                        path.addLine(to: CGPoint(x: xPos, y: plotArea.origin.y + plotArea.height))
                                    }
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .foregroundColor(Color.white.opacity(0.7))

                                    // 简化水平线计算
                                    let prices = holders.compactMap { Double($0.holders ?? 0) }
                                    let minP = prices.min() ?? 0
                                    let maxP = prices.max() ?? 1
                                    if maxP > minP {
                                        let ratio = (hValue - minP) / (maxP - minP)
                                        let yPos = plotArea.origin.y + plotArea.height * (1 - ratio)

                                        Path { path in
                                            path.move(to: CGPoint(x: plotArea.origin.x, y: yPos))
                                            path.addLine(to: CGPoint(x: plotArea.origin.x + plotArea.width, y: yPos))
                                        }
                                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                        .foregroundColor(Color(hex: "1E88E5").opacity(0.7))
                                    }
                                }
                            }
                        }
                        // 显示选中的季度信息
                        if let index = selectedQuarterIndex, index < holders.count {
                            HStack {
                                Text(holders[index].date ?? "")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                Text(": \(holders[index].holders ?? 0)户")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color(hex: "1E88E5"))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 0)
                            .background(Color(hex: "1E1E1E"))
                            .cornerRadius(8)
                        }

                        // 统计信息
                        HStack {
                            VStack(alignment: .leading) {
                                Text("最新股东")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text("\(holders.last?.holders ?? 0)")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                            Spacer()
                            let latest = holders.last?.holders ?? 0
                            let earliest = holders.first?.holders ?? 0
                            let change = earliest > 0 ? Double(latest - earliest) / Double(earliest) * 100 : 0
                            VStack(alignment: .trailing) {
                                Text("5年变化")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(String(format: "%.1f%%", change))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundColor(change >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                            }
                        }
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }

                // K线趋势图
                if isLoading {
                    VStack {
                        ProgressView()
                            .frame(height: 200)
                        Text("加载中...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                } else if let kline = klineDataForSelectedPeriod, !kline.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("股价趋势（\(selectedKlinePeriod.rawValue)线）")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                        }

                        // 周期选择器
                        HStack(spacing: 12) {
                            ForEach(KlinePeriod.allCases, id: \.self) { period in
                                Button {
                                    selectedKlinePeriod = period
                                    selectedKlineIndex = nil
                                } label: {
                                    Text(period.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(selectedKlinePeriod == period ? .semibold : .regular)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 0)
                                        .background(selectedKlinePeriod == period ? Color(hex: "1E88E5") : Color(hex: "2C2C2C"))
                                        .foregroundColor(selectedKlinePeriod == period ? .white : .gray)
                                        .cornerRadius(16)
                                }
                            }
                        }

                        Chart {
                            ForEach(kline.indices, id: \.self) { index in
                                LineMark(
                                    x: .value("日期", index),
                                    y: .value("收盘价", kline[index].close ?? 0)
                                )
                                .foregroundStyle(Color(hex: "FFC107"))

                                // 显示选中点的光标
                                if let selectedIdx = selectedKlineIndex, selectedIdx == index {
                                    PointMark(
                                        x: .value("日期", index),
                                        y: .value("收盘价", kline[index].close ?? 0)
                                    )
                                    .foregroundStyle(Color.white)
                                    .symbolSize(80)
                                }
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .trailing) { _ in
                                AxisValueLabel()
                                    .foregroundStyle(Color.gray)
                            }
                        }
                        .chartOverlay { proxy in
                            GeometryReader { geometry in
                                let plotArea = geometry[proxy.plotAreaFrame]

                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                let xPos = value.location.x
                                                let cWidth = plotArea.width
                                                let xOff = plotArea.origin.x
                                                if kline.count > 0 {
                                                    let idx = Int(((xPos - xOff) / cWidth) * CGFloat(kline.count))
                                                    let clamped = max(0, min(idx, kline.count - 1))
                                                    selectedKlineIndex = clamped
                                                }
                                            }
                                            .onEnded { _ in }
                                    )

                                if let index = selectedKlineIndex, index < kline.count {
                                    let price = Double(kline[index].close ?? 0)
                                    let cWidth = plotArea.width
                                    let xOff = plotArea.origin.x
                                    let xPos = xOff + (CGFloat(index) + 0.5) / CGFloat(kline.count) * cWidth

                                    // 垂直线
                                    Path { path in
                                        path.move(to: CGPoint(x: xPos, y: plotArea.origin.y))
                                        path.addLine(to: CGPoint(x: xPos, y: plotArea.origin.y + plotArea.height))
                                    }
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .foregroundColor(Color.white.opacity(0.7))

                                    // 简化水平线计算
                                    let prices = kline.compactMap { Double($0.close ?? 0) }
                                    let minP = prices.min() ?? 0
                                    let maxP = prices.max() ?? 1
                                    if maxP > minP {
                                        let ratio = (price - minP) / (maxP - minP)
                                        let yPos = plotArea.origin.y + plotArea.height * (1 - ratio)

                                        Path { path in
                                            path.move(to: CGPoint(x: plotArea.origin.x, y: yPos))
                                            path.addLine(to: CGPoint(x: plotArea.origin.x + plotArea.width, y: yPos))
                                        }
                                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                        .foregroundColor(Color(hex: "FFC107").opacity(0.7))
                                    }
                                }
                            }
                        }

                        // 光标信息显示
                        if let index = selectedKlineIndex, index < kline.count {
                            let data = kline[index]
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(data.date ?? "")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading) {
                                            Text("开")
                                                .font(.system(size: 10))
                                                .foregroundColor(.gray)
                                            Text(String(format: "%.2f", data.open ?? 0))
                                                .font(.caption)
                                                .foregroundColor(.white)
                                        }
                                        VStack(alignment: .leading) {
                                            Text("高")
                                                .font(.system(size: 10))
                                                .foregroundColor(.gray)
                                            Text(String(format: "%.2f", data.high ?? 0))
                                                .font(.caption)
                                                .foregroundColor(Color(hex: "F44336"))
                                        }
                                        VStack(alignment: .leading) {
                                            Text("低")
                                                .font(.system(size: 10))
                                                .foregroundColor(.gray)
                                            Text(String(format: "%.2f", data.low ?? 0))
                                                .font(.caption)
                                                .foregroundColor(Color(hex: "4CAF50"))
                                        }
                                        VStack(alignment: .leading) {
                                            Text("收")
                                                .font(.system(size: 10))
                                                .foregroundColor(.gray)
                                            Text(String(format: "%.2f", data.close ?? 0))
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                        }
                                        VStack(alignment: .leading) {
                                            Text("量")
                                                .font(.system(size: 10))
                                                .foregroundColor(.gray)
                                            Text(formatVolume(data.volume ?? 0))
                                                .font(.caption)
                                                .foregroundColor(Color(hex: "FFC107"))
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "2C2C2C"))
                            .cornerRadius(8)
                        } else {
                            // 默认显示最新数据
                            HStack {
                                Text("最新: ")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(String(format: "¥%.2f", kline.last?.close ?? 0))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Spacer()
                                if kline.count >= 2 {
                                    let change = ((kline.last?.close ?? 0) - (kline.first?.close ?? 0)) / (kline.first?.close ?? 1) * 100
                                    Text("累计: \(String(format: "%.1f%%", change))")
                                        .font(.caption)
                                        .foregroundColor(change >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }

                // 5年涨跌
                if let change5y = stock.change_5y {
                    HStack {
                        Text("5年涨跌")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Text(String(format: "%.2f%%", change5y))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(change5y >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }

                // 价格分位 - 使用Gauge仪表盘
                if let pricePct = stock.price_percentile {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("当前价格历史分位")
                            .font(.headline)
                            .foregroundColor(.white)

                        HStack {
                            Gauge(value: pricePct, in: 0...100) {
                                Text("价格分位")
                            } currentValueLabel: {
                                Text("\(Int(pricePct))%")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            .gaugeStyle(.accessoryCircular)
                            .tint(valuationColor(pricePct))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("价格分位")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text(pricePositionDescription(pricePct))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.leading)
                        }
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }

                // MACD底背离
                if let macd = stock.macd_divergence {
                    let hasDivergence = (macd.daily == true || macd.weekly == true || macd.monthly == true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("MACD底背离信号")
                            .font(.headline)
                            .foregroundColor(.white)

                        HStack {
                            Image(systemName: hasDivergence ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(hasDivergence ? Color(hex: "4CAF50") : Color(hex: "F44336"))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(hasDivergence ? "已出现底背离信号" : "未出现底背离信号")
                                    .font(.subheadline)
                                    .foregroundColor(.white)

                                Text(hasDivergence ? "股价创新低但MACD未创新低，反弹概率较大" : "无明显底背离信号")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }

                            Spacer()
                        }

                        // 详细周期
                        HStack(spacing: 20) {
                            VStack {
                                Text("日线")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Image(systemName: (macd.daily ?? false) ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundColor((macd.daily ?? false) ? Color(hex: "4CAF50") : .gray)
                            }
                            VStack {
                                Text("周线")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Image(systemName: (macd.weekly ?? false) ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundColor((macd.weekly ?? false) ? Color(hex: "4CAF50") : .gray)
                            }
                            VStack {
                                Text("月线")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Image(systemName: (macd.monthly ?? false) ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundColor((macd.monthly ?? false) ? Color(hex: "4CAF50") : .gray)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }

                // 趋势分析
                if let trend = stock.trend_analysis {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("趋势分析")
                            .font(.headline)
                            .foregroundColor(.white)

                        HStack {
                            VStack {
                                Text("短期")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(trend.short ?? "-")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            }
                            Spacer()
                            VStack {
                                Text("中期")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(trend.medium ?? "-")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            }
                            Spacer()
                            VStack {
                                Text("长期")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(trend.long ?? "-")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }

                // 筹码集中度
                if let chip = stock.chip_concentration {
                    let chipPercent = chip * 100
                    VStack(alignment: .leading, spacing: 12) {
                        Text("筹码集中度")
                            .font(.headline)
                            .foregroundColor(.white)

                        HStack {
                            Gauge(value: chipPercent, in: 0...100) {
                                Text("CR指标")
                            } currentValueLabel: {
                                Text("\(Int(chipPercent))%")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            .gaugeStyle(.accessoryCircular)
                            .tint(chipColor(chipPercent))

                            VStack(alignment: .leading, spacing: 4) {
                                chipLabel(chipPercent)
                                Text(chipDescription(chipPercent))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.leading)
                        }
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .background(Color(hex: "121212"))
        .navigationTitle(stock.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadStockDetail()
        }
    }

    // 根据选择的周期返回对应的K线数据
    private var klineDataForSelectedPeriod: [Stock.KlineData]? {
        guard let stock = detailedStock else { return nil }
        switch selectedKlinePeriod {
        case .daily:
            return stock.kline_daily
        case .weekly:
            return stock.kline_weekly
        case .monthly:
            return stock.kline_monthly
        }
    }

    // 加载股票详情（使用手动解析）
    @MainActor
    private func loadStockDetail() {
        guard let url = URL(string: "\(baseURL)/stock/\(stock.code)") else { return }

        isLoading = true
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    // 使用StockAPI手动解析详情页响应
                    let stock = StockAPI.parseDetailResponse(data)
                    if stock != nil {
                        print("加载详情成功: 日K=\(stock?.kline_daily?.count ?? 0), 周K=\(stock?.kline_weekly?.count ?? 0), 月K=\(stock?.kline_monthly?.count ?? 0)")
                    }
                    detailedStock = stock
                }
            } catch {
                print("加载详情失败: \(error)")
            }
            isLoading = false
        }
    }

    // 估值颜色
    func valuationColor(_ percentile: Double) -> Color {
        if percentile < 20 { return Color(hex: "4CAF50") }
        else if percentile < 50 { return Color(hex: "1E88E5") }
        else if percentile < 80 { return Color(hex: "FFC107") }
        else { return Color(hex: "F44336") }
    }

    // 估值标签
    func valuationLabel(_ percentile: Double) -> some View {
        Group {
            if percentile < 20 { Text("极低估值") }
            else if percentile < 40 { Text("低估值") }
            else if percentile < 60 { Text("合理估值") }
            else if percentile < 80 { Text("高估值") }
            else { Text("极高估值") }
        }
        .font(.subheadline)
        .foregroundColor(valuationColor(percentile))
    }

    // 价格位置描述
    func pricePositionDescription(_ percentile: Double) -> String {
        if percentile < 20 { return "历史低位，适合布局" }
        else if percentile < 40 { return "价格偏低，关注机会" }
        else if percentile < 60 { return "价格合理" }
        else if percentile < 80 { return "价格偏高，注意风险" }
        else { return "风险较大，谨慎参与" }
    }

    // 筹码颜色
    func chipColor(_ value: Double) -> Color {
        if value > 80 { return Color(hex: "4CAF50") }
        else if value > 60 { return Color(hex: "1E88E5") }
        else if value > 40 { return Color(hex: "FFC107") }
        else { return Color(hex: "F44336") }
    }

    // 筹码标签
    func chipLabel(_ value: Double) -> some View {
        Group {
            if value > 80 { Text("高度集中") }
            else if value > 60 { Text("相对集中") }
            else if value > 40 { Text("相对分散") }
            else { Text("高度分散") }
        }
        .font(.subheadline)
        .foregroundColor(chipColor(value))
    }

    // 筹码描述
    func chipDescription(_ value: Double) -> String {
        if value > 80 { return "主力高度控盘，可能快速拉升" }
        else if value > 60 { return "筹码集中，上涨概率大" }
        else if value > 40 { return "筹码分布均衡" }
        else { return "筹码分散，上涨动力不足" }
    }

    // 格式化成交量
    func formatVolume(_ volume: Double) -> String {
        if volume >= 100000000 {
            return String(format: "%.2f亿", volume / 100000000)
        } else if volume >= 10000 {
            return String(format: "%.2f万", volume / 10000)
        } else {
            return String(format: "%.0f", volume)
        }
    }
}

