import SwiftUI
import Charts

struct StockDetailPageView: View {
    let currentIndex: Int
    let allStocks: [Stock]
    @Binding var currentPage: Int

    @State private var selectedQuarterIndex: Int? = nil
    @State private var detailedStocks: [String: Stock] = [:]
    @State private var selectedKlinePeriod: KlinePeriod = .daily
    @State private var selectedKlineIndex: Int? = nil

    private let baseURL = "http://8.163.91.16:5000/api/v1"

    enum KlinePeriod: String, CaseIterable {
        case daily = "日"
        case weekly = "周"
        case monthly = "月"
    }

    var body: some View {
        TabView(selection: $currentPage) {
            ForEach(Array(allStocks.enumerated()), id: \.offset) { index, stock in
                StockDetailContent(
                    stock: stock,
                    detailedStock: detailedStocks[stock.code],
                    selectedQuarterIndex: $selectedQuarterIndex,
                    selectedKlinePeriod: $selectedKlinePeriod,
                    selectedKlineIndex: $selectedKlineIndex,
                    loadDetail: { loadStockDetail(stockCode: stock.code) }
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color(hex: "121212"))
        .onChange(of: currentPage) { newPage in
            // 切换页面时预加载相邻股票的详情
            preloadAdjacentDetails(newPage: newPage)
        }
    }

    private func preloadAdjacentDetails(newPage: Int) {
        // 预加载前后3个股票的详情
        let range = max(0, newPage - 1)...min(allStocks.count - 1, newPage + 1)
        for i in range {
            let code = allStocks[i].code
            if detailedStocks[code] == nil {
                loadStockDetail(stockCode: code)
            }
        }
    }

    private func loadStockDetail(stockCode: String) {
        Task {
            guard let url = URL(string: "\(baseURL)/stock/\(stockCode)") else { return }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if let stock = StockAPI.parseDetailResponse(data) {
                        await MainActor.run {
                            detailedStocks[stockCode] = stock
                        }
                    }
                }
            } catch {
                print("加载详情失败: \(error)")
            }
        }
    }
}

struct StockDetailContent: View {
    let stock: Stock
    let detailedStock: Stock?
    @Binding var selectedQuarterIndex: Int?
    @Binding var selectedKlinePeriod: StockDetailPageView.KlinePeriod
    @Binding var selectedKlineIndex: Int?
    let loadDetail: () -> Void

    @State private var isLoading = false

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
                   股东趋势图(holders: holders)
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
                    k线趋势图(kline: kline)
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

                // 价格分位
                if let pricePct = stock.price_percentile {
                    价格分位View(pricePct: pricePct)
                }

                // MACD底背离
                if let macd = stock.macd_divergence {
                    macd底背离View(macd: macd)
                }

                // 趋势分析
                if let trend = stock.trend_analysis {
                    趋势分析View(trend: trend)
                }

                // 筹码集中度
                if let chip = stock.chip_concentration {
                    筹码集中度View(chip: chip)
                }
            }
            .padding()
        }
        .background(Color(hex: "121212"))
        .navigationTitle(stock.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadDetail()
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

    // MARK: - 子视图组件

    @ViewBuilder
    func 股东趋势图(holders: [Stock.HolderData]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("股东人数趋势")
                .font(.headline)
                .foregroundColor(.white)

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

                        Path { path in
                            path.move(to: CGPoint(x: xPos, y: plotArea.origin.y))
                            path.addLine(to: CGPoint(x: xPos, y: plotArea.origin.y + plotArea.height))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundColor(Color.white.opacity(0.7))

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
                .padding(.vertical, 6)
                .background(Color(hex: "1E1E1E"))
                .cornerRadius(8)
            }

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

    @ViewBuilder
    func k线趋势图(kline: [Stock.KlineData]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("股价趋势（\(selectedKlinePeriod.rawValue)线）")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }

            HStack(spacing: 12) {
                ForEach(StockDetailPageView.KlinePeriod.allCases, id: \.self) { period in
                    Button {
                        selectedKlinePeriod = period
                        selectedKlineIndex = nil
                    } label: {
                        Text(period.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedKlinePeriod == period ? .semibold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
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

                        Path { path in
                            path.move(to: CGPoint(x: xPos, y: plotArea.origin.y))
                            path.addLine(to: CGPoint(x: xPos, y: plotArea.origin.y + plotArea.height))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundColor(Color.white.opacity(0.7))

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

    @ViewBuilder
    func 价格分位View(pricePct: Double) -> some View {
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

    @ViewBuilder
    func macd底背离View(macd: Stock.MACDDivergence) -> some View {
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

    @ViewBuilder
    func 趋势分析View(trend: Stock.TrendAnalysis) -> some View {
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

    @ViewBuilder
    func 筹码集中度View(chip: Double) -> some View {
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

    // MARK: - 辅助函数

    func valuationColor(_ percentile: Double) -> Color {
        if percentile < 20 { return Color(hex: "4CAF50") }
        else if percentile < 50 { return Color(hex: "1E88E5") }
        else if percentile < 80 { return Color(hex: "FFC107") }
        else { return Color(hex: "F44336") }
    }

    func pricePositionDescription(_ percentile: Double) -> String {
        if percentile < 20 { return "历史低位，适合布局" }
        else if percentile < 40 { return "价格偏低，关注机会" }
        else if percentile < 60 { return "价格合理" }
        else if percentile < 80 { return "价格偏高，注意风险" }
        else { return "风险较大，谨慎参与" }
    }

    func chipColor(_ value: Double) -> Color {
        if value > 80 { return Color(hex: "4CAF50") }
        else if value > 60 { return Color(hex: "1E88E5") }
        else if value > 40 { return Color(hex: "FFC107") }
        else { return Color(hex: "F44336") }
    }

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

    func chipDescription(_ value: Double) -> String {
        if value > 80 { return "主力高度控盘，可能快速拉升" }
        else if value > 60 { return "筹码集中，上涨概率大" }
        else if value > 40 { return "筹码分布均衡" }
        else { return "筹码分散，上涨动力不足" }
    }

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