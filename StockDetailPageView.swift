import SwiftUI
import Charts
import UIKit

struct StockDetailPageView: View {
    let currentIndex: Int
    let allStocks: [Stock]
    @Binding var currentPage: Int

    @State private var selectedQuarterIndex: Int? = nil
    @State private var detailedStocks: [String: Stock] = [:]
    @State private var financialHistoryStocks: [String: [Stock.FinancialHistoryItem]] = [:]
    @State private var selectedKlinePeriod: KlinePeriod = .daily
    @State private var selectedKlineIndex: Int? = nil
    @State private var selectedFinancialIndex: Int? = nil

    enum KlinePeriod: String, CaseIterable {
        case daily = "日"
        case weekly = "周"
        case monthly = "月"
    }

    // 打开东方财富App
    func openInEastMoney(code: String) {
        guard code.count == 6 else { return }

        let prefix: String
        if code.hasPrefix("6") || code.hasPrefix("9") || code.hasPrefix("688") {
            prefix = "sh"
        } else {
            prefix = "sz"
        }

        let appScheme = "eastmoney://"
        let webURL = "https://quote.eastmoney.com/\(prefix)\(code).html"

        if let url = URL(string: appScheme), UIApplication.shared.canOpenURL(url) {
            // 唤起App同时复制股票代码，方便在App里粘贴搜索
            UIPasteboard.general.string = code
            UIApplication.shared.open(url)
        } else if let url = URL(string: webURL) {
            UIApplication.shared.open(url)
        }
    }

    /// 只渲染当前页前后各 2 页的窗口，避免 TabView 一次性创建全部 300-500 个 StockDetailContent 导致内存爆炸黑屏
    private var pageWindow: (stocks: [Stock], startIndex: Int) {
        guard !allStocks.isEmpty else { return ([], 0) }
        // 股票数量少时直接全部渲染，无需窗口优化
        if allStocks.count <= 10 { return (allStocks, 0) }
        let half = 2
        let idealEnd = currentPage + half
        let start: Int
        if idealEnd > allStocks.count - 1 {
            start = max(0, allStocks.count - 1 - 2 * half)
        } else {
            start = max(0, currentPage - half)
        }
        let end = min(allStocks.count - 1, max(start, idealEnd))
        return (Array(allStocks[start...end]), start)
    }

    var body: some View {
        let (windowStocks, startIdx) = pageWindow

        TabView(selection: $currentPage) {
            ForEach(Array(windowStocks.enumerated()), id: \.element.id) { offset, stock in
                let realIndex = startIdx + offset
                StockDetailContent(
                    stock: stock,
                    detailedStock: detailedStocks[stock.code],
                    financialHistory: financialHistoryStocks[stock.code],
                    selectedQuarterIndex: $selectedQuarterIndex,
                    selectedKlinePeriod: $selectedKlinePeriod,
                    selectedKlineIndex: $selectedKlineIndex,
                    selectedFinancialIndex: $selectedFinancialIndex,
                    loadDetail: { loadStockDetail(stock.code) },
                    loadFinancialHistory: loadFinancialHistory
                )
                .tag(realIndex)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color(hex: "121212"))
        .onChange(of: currentPage) { newPage in
            preloadAdjacentDetails(newPage: newPage)
        }
    }

    private func preloadAdjacentDetails(newPage: Int) {
        // 预加载前后3个股票的详情
        let range = max(0, newPage - 1)...min(allStocks.count - 1, newPage + 1)
        for i in range {
            let code = allStocks[i].code
            if detailedStocks[code] == nil {
                loadStockDetail(code)
            }
            if financialHistoryStocks[code] == nil {
                loadFinancialHistory(code)
            }
        }
        // 淘汰远离当前页的缓存，防止内存无界增长
        let keepRange = max(0, newPage - 3)...min(allStocks.count - 1, newPage + 3)
        let keepCodes = Set(keepRange.map { allStocks[$0].code })
        detailedStocks = detailedStocks.filter { keepCodes.contains($0.key) }
        financialHistoryStocks = financialHistoryStocks.filter { keepCodes.contains($0.key) }
    }

    private func loadStockDetail(_ stockCode: String) {
        Task {
            do {
                let data = try await APIClient.getData("/stock/\(stockCode)", retries: 1)
                if let stock = StockAPI.parseDetailResponse(data) {
                    await MainActor.run {
                        detailedStocks[stockCode] = stock
                    }
                }
            } catch {
                print("加载详情失败: \(error)")
            }
        }
    }

    private func loadFinancialHistory(_ stockCode: String) {
        Task {
            do {
                let result: FinancialHistoryResponse = try await APIClient.get("/stock/\(stockCode)/financial_history", retries: 1)
                if let history = result.data?.history {
                    await MainActor.run {
                        financialHistoryStocks[stockCode] = history
                    }
                }
            } catch {
                print("加载财务历史失败: \(error)")
            }
        }
    }
}

struct StockDetailContent: View {
    let stock: Stock
    let detailedStock: Stock?
    let financialHistory: [Stock.FinancialHistoryItem]?
    @Binding var selectedQuarterIndex: Int?
    @Binding var selectedKlinePeriod: StockDetailPageView.KlinePeriod
    @Binding var selectedKlineIndex: Int?
    @Binding var selectedFinancialIndex: Int?
    let loadDetail: () -> Void
    let loadFinancialHistory: (String) -> Void

    @State private var isLoading = false
    @State private var showTradeSheet = false
    @State private var tradeQuantity = ""
    @State private var selectedTradeAction = 0  // 0=买入, 1=卖出

    // 打开东方财富App
    func openInEastMoney() {
        let code = stock.code
        guard code.count == 6 else { return }

        let prefix: String
        if code.hasPrefix("6") || code.hasPrefix("9") || code.hasPrefix("688") {
            prefix = "sh"
        } else {
            prefix = "sz"
        }

        let appScheme = "eastmoney://"
        let webURL = "https://quote.eastmoney.com/\(prefix)\(code).html"

        if let url = URL(string: appScheme), UIApplication.shared.canOpenURL(url) {
            UIPasteboard.general.string = code
            UIApplication.shared.open(url)
        } else if let url = URL(string: webURL) {
            UIApplication.shared.open(url)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 股票基本信息（板块）
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        openInEastMoney()
                    } label: {
                        HStack(spacing: 4) {
                            Text(stock.name)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Image(systemName: "arrow.up.forward.square")
                                .font(.caption)
                                .foregroundColor(Color(hex: "1E88E5"))
                        }
                    }
                    HStack {
                        Text(stock.code)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Spacer()
                        // 模拟交易按钮
                        Button {
                            showTradeSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "cart.fill.badge.plus")
                                Text("买入")
                            }
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(hex: "4CAF50"))
                            .cornerRadius(6)
                        }
                    }
                    if let sector = stock.sector, !sector.isEmpty {
                        Text(sector)
                            .font(.caption)
                            .foregroundColor(Color(hex: "1E88E5"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "1E88E5").opacity(0.2))
                            .cornerRadius(4)
                    }
                    // 概念板块标签
                    if let concepts = stock.concepts, !concepts.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(concepts.enumerated()), id: \.offset) { index, concept in
                                    Text(concept)
                                        .font(.caption2)
                                        .foregroundColor(Color(hex: conceptLabelColor(index)))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color(hex: conceptLabelColor(index)).opacity(0.15))
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                    // 大涨原因
                    if let surgeReason = stock.surge_reason, let c_pct = stock.change_pct, c_pct >= 5.0 {
                        HStack(spacing: 6) {
                            Image(systemName: c_pct >= 9.9 ? "bolt.fill" : "flame.fill")
                                .foregroundColor(Color(hex: "FF6B00"))
                                .font(.caption)
                            Text("大涨原因:")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(surgeReason)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(Color(hex: "FF6B00"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: "FF6B00").opacity(0.10))
                        .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(hex: "1E1E1E"))
                .cornerRadius(12)

                // 股东人数趋势
                if let holders = stock.holders_trend, !holders.isEmpty {
                   股东趋势图(holders: holders)
                }

                // 财务数据趋势
                if let history = financialHistory, !history.isEmpty {
                    财务趋势图(history: history)
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

                // 价格分位
                if let pricePct = stock.price_percentile {
                    价格分位View(pricePct: pricePct)
                }

                // 趋势分析
                if let trend = stock.trend_analysis {
                    趋势分析View(trend: trend)
                }

                // 筹码集中度
                if let chip = stock.chip_concentration {
                    筹码集中度View(chip: chip)
                }

                // 退市风险分析
                退市风险分析View(stock: stock)
            }
            .padding()
        }
        .background(Color(hex: "121212"))
        .navigationTitle(stock.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadDetail()
            loadFinancialHistory(stock.code)
        }
        .sheet(isPresented: $showTradeSheet) {
            TradeSheetView(
                stock: stock,
                isPresented: $showTradeSheet,
                selectedAction: $selectedTradeAction,
                quantity: $tradeQuantity
            )
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

    // 财务数据详情文本
    private func financialDetailText() -> String {
        guard let stock = detailedStock else { return "" }
        var parts: [String] = []
        if let yoy = stock.net_profit_yoy, !yoy.isEmpty {
            parts.append("同比\(yoy)")
        }
        if let qoq = stock.net_profit_qoq, !qoq.isEmpty {
            parts.append("环比\(qoq)")
        }
        if let roeVal = stock.roe, !roeVal.isEmpty {
            parts.append("ROE \(roeVal)")
        }
        return parts.joined(separator: " | ")
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

    // 财务数据趋势图
    @ViewBuilder
    func 财务趋势图(history: [Stock.FinancialHistoryItem]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("净利润趋势")
                .font(.headline)
                .foregroundColor(.white)

            // 解析数据 - 按时间排序
            let sortedHistory = history.sorted { ($0.report_date ?? "") < ($1.report_date ?? "") }

            // 同比数据
            let yoyData = sortedHistory.compactMap { item -> (String, Double)? in
                guard let yoy = item.net_profit_yoy, !yoy.isEmpty else { return nil }
                let label = item.quarter ?? item.report_name ?? ""
                let value = Double(yoy.replacingOccurrences(of: "%", with: "")) ?? 0
                return (label, value)
            }

            // 环比数据
            let qoqData = sortedHistory.compactMap { item -> (String, Double)? in
                guard let qoq = item.net_profit_qoq, !qoq.isEmpty else { return nil }
                let label = item.quarter ?? item.report_name ?? ""
                let value = Double(qoq.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")) ?? 0
                return (label, value)
            }

            if yoyData.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                // 获取所有季度标签
                let allLabels = yoyData.map { $0.0 }

                // 同比趋势图
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(Color(hex: "4CAF50"))
                            .frame(width: 8, height: 8)
                        Text("同比 (YoY)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }

                    Chart {
                        ForEach(yoyData.indices, id: \.self) { index in
                            let item = yoyData[index]
                            LineMark(
                                x: .value("季度", item.0),
                                y: .value("同比", item.1)
                            )
                            .foregroundStyle(Color(hex: "4CAF50"))

                            PointMark(
                                x: .value("季度", item.0),
                                y: .value("同比", item.1)
                            )
                            .foregroundStyle(Color(hex: "4CAF50"))
                        }
                    }
                    .frame(height: 140)
                    .chartXAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisValueLabel()
                                .font(.caption2)
                                .foregroundStyle(Color.gray)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisValueLabel()
                                .foregroundStyle(Color.gray)
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            let plotArea = geometry[proxy.plotAreaFrame]
                            let cWidth = plotArea.width
                            let xOff = plotArea.origin.x

                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let xPos = value.location.x
                                            if allLabels.count > 0 {
                                                let idx = Int(((xPos - xOff) / cWidth) * CGFloat(allLabels.count))
                                                selectedFinancialIndex = max(0, min(idx, allLabels.count - 1))
                                            }
                                        }
                                )

                            // 十字线
                            if let idx = selectedFinancialIndex, idx < allLabels.count {
                                let xPos = xOff + (CGFloat(idx) + 0.5) / CGFloat(allLabels.count) * cWidth
                                Path { path in
                                    path.move(to: CGPoint(x: xPos, y: plotArea.origin.y))
                                    path.addLine(to: CGPoint(x: xPos, y: plotArea.origin.y + plotArea.height))
                                }
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundColor(Color.white.opacity(0.7))
                            }
                        }
                    }

                    // 同比数值
                    if let idx = selectedFinancialIndex, idx < yoyData.count {
                        let item = yoyData[idx]
                        Text("\(item.0): \(String(format: "%.1f%%", item.1))")
                            .font(.caption)
                            .foregroundColor(Color(hex: "4CAF50"))
                    }
                }
                .padding()
                .background(Color(hex: "1E1E1E"))
                .cornerRadius(8)

                // 环比趋势图
                if !qoqData.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle()
                                .fill(Color(hex: "FFEB3B"))
                                .frame(width: 8, height: 8)
                            Text("环比 (QoQ)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }

                        let qoqLabels = qoqData.map { $0.0 }

                        Chart {
                            ForEach(qoqData.indices, id: \.self) { index in
                                let item = qoqData[index]
                                LineMark(
                                    x: .value("季度", item.0),
                                    y: .value("环比", item.1)
                                )
                                .foregroundStyle(Color(hex: "FFEB3B"))

                                PointMark(
                                    x: .value("季度", item.0),
                                    y: .value("环比", item.1)
                                )
                                .foregroundStyle(Color(hex: "FFEB3B"))
                            }
                        }
                        .frame(height: 140)
                        .chartXAxis {
                            AxisMarks(values: .automatic) { _ in
                                AxisValueLabel()
                                    .font(.caption2)
                                    .foregroundStyle(Color.gray)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in
                                AxisValueLabel()
                                    .foregroundStyle(Color.gray)
                            }
                        }
                        .chartOverlay { proxy in
                            GeometryReader { geometry in
                                let plotArea = geometry[proxy.plotAreaFrame]
                                let cWidth = plotArea.width
                                let xOff = plotArea.origin.x

                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                let xPos = value.location.x
                                                if qoqLabels.count > 0 {
                                                    let idx = Int(((xPos - xOff) / cWidth) * CGFloat(qoqLabels.count))
                                                    selectedFinancialIndex = max(0, min(idx, qoqLabels.count - 1))
                                                }
                                            }
                                    )

                                if let idx = selectedFinancialIndex, idx < qoqLabels.count {
                                    let xPos = xOff + (CGFloat(idx) + 0.5) / CGFloat(qoqLabels.count) * cWidth
                                    Path { path in
                                        path.move(to: CGPoint(x: xPos, y: plotArea.origin.y))
                                        path.addLine(to: CGPoint(x: xPos, y: plotArea.origin.y + plotArea.height))
                                    }
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .foregroundColor(Color.white.opacity(0.7))
                                }
                            }
                        }

                        // 环比数值
                        if let idx = selectedFinancialIndex, idx < qoqData.count {
                            let item = qoqData[idx]
                            Text("\(item.0): \(String(format: "%.1f%%", item.1))")
                                .font(.caption)
                                .foregroundColor(Color(hex: "FFEB3B"))
                        }
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(8)
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
    func 趋势分析View(trend: Stock.TrendAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("趋势分析")
                .font(.headline)
                .foregroundColor(.white)

            HStack {
                趋势标签(title: "短期", value: trend.short)
                Spacer()
                趋势标签(title: "中期", value: trend.medium)
                Spacer()
                趋势标签(title: "长期", value: trend.long)
            }
        }
        .padding()
        .background(Color(hex: "1E1E1E"))
        .cornerRadius(12)
    }

    @ViewBuilder
    func 趋势标签(title: String, value: String?) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
            趋势图标(value: value ?? "-")
            Text(趋势文字(value: value ?? "-"))
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    @ViewBuilder
    func 趋势图标(value: String) -> some View {
        switch value {
        case "上涨趋势":
            Image(systemName: "arrow.up.right")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(hex: "FF5252"))
        case "下跌趋势":
            Image(systemName: "arrow.down.right")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(hex: "4CAF50"))
        default:
            Image(systemName: "minus")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(hex: "FFEB3B"))
        }
    }

    func 趋势文字(value: String) -> String {
        switch value {
        case "上涨趋势": return "上涨"
        case "下跌趋势": return "下跌"
        case "震荡筑底", "长期筑底": return "筑底"
        case "震荡": return "震荡"
        default: return "未知"
        }
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

    func conceptLabelColor(_ index: Int) -> String {
        let colors = ["4FC3F7", "AED581", "FFB74D", "CE93D8", "EF5350",
                      "26C6DA", "9CCC65", "FFA726", "AB47BC", "42A5F5"]
        return colors[index % colors.count]
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

// 退市风险分析视图
struct 退市风险分析View: View {
    let stock: Stock

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(hex: "FFEB3B"))
                Text("退市风险分析")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            // 风险规则列表
            VStack(spacing: 8) {
                ForEach(analyzeRisks(), id: \.rule) { item in
                    HStack {
                        // 规则名称
                        Text(item.rule)
                            .font(.subheadline)
                            .foregroundColor(.white)

                        Spacer()

                        // 状态标签
                        Text(item.status)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(backgroundColor(for: item.status))
                            .cornerRadius(4)

                        // 详情
                        Text(item.detail)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 160, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(hex: "1E1E1E"))
        .cornerRadius(12)
    }

    private func analyzeRisks() -> [(rule: String, status: String, detail: String)] {
        var results: [(rule: String, status: String, detail: String)] = []
        let code = stock.code
        let isGEM = code.hasPrefix("30")
        let isSTAR = code.hasPrefix("68")

        // ===== 财务类规则 =====

        // 1. 净利润+营收组合指标（各板块不同门槛）
        // 主板: 净利润为负+营收<3亿
        // 创业板: 净利润为负+营收<1亿
        // 科创板: 净利润为负+营收<5000万
        let revenueThreshold = isSTAR ? "5000万" : (isGEM ? "1亿" : "3亿")
        let isProfitNegative = checkProfitNegative()
        let isRevenueLow = checkRevenueLow(isGEM: isGEM, isSTAR: isSTAR)

        if isProfitNegative && isRevenueLow {
            results.append(("净利润+营收(\(revenueThreshold))", "危险", "触发*ST；次年仍不达标→退市"))
        } else if isProfitNegative {
            results.append(("净利润+营收(\(revenueThreshold))", "警示", "净利为负，若营收<\(revenueThreshold)→*ST"))
        } else if let yoy = stock.net_profit_yoy {
            let clean = yoy.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")
            if let yoyVal = Double(clean), yoyVal >= 0 {
                results.append(("净利润+营收(\(revenueThreshold))", "安全", "净利同比+\(Int(yoyVal))%，营收\(stock.revenue ?? "?")"))
            } else {
                results.append(("净利润+营收(\(revenueThreshold))", "未知", "净利为负，营收数据缺失"))
            }
        } else if let revenue = stock.revenue {
            results.append(("净利润+营收(\(revenueThreshold))", "安全", "营收\(revenue)，高于\(revenueThreshold)门槛"))
        } else {
            results.append(("净利润+营收(\(revenueThreshold))", "未知", "净利及营收数据缺失"))
        }

        // 2. ROE（辅助指标，非直接ST标准）
        if let roe = stock.roe {
            let clean = roe.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")
            if let roeVal = Double(clean), roeVal < 0 {
                results.append(("ROE（辅助）", "警示", "ROE为负，持续亏损将触发净利+营收*ST"))
            } else if let roeVal = Double(clean), roeVal >= 0 {
                results.append(("ROE（辅助）", "安全", "ROE为\(roe)%"))
            } else {
                results.append(("ROE（辅助）", "未知", "无法解析"))
            }
        } else {
            results.append(("ROE（辅助）", "未知", "缺少数据"))
        }

        // 3. 净资产为负
        if let bvVal = stock.book_value_per_share, bvVal < 0 {
            results.append(("净资产为负", "危险", "触发*ST；次年仍为负→退市"))
        } else if let bvVal = stock.book_value_per_share {
            results.append(("净资产为负", "安全", "每股净资产\(String(format: "%.2f", bvVal))元"))
        } else {
            results.append(("净资产为负", "未知", "需每股净资产"))
        }

        // 4. 审计报告
        results.append(("审计报告非标", "需人工核验", "无法表示/否定意见→*ST→退市"))

        // 5. 分红不达标（连续3年不分红 → ST）
        if let divCount = stock.dividend_count {
            if divCount == 0 {
                results.append(("分红不达标", "警示", "从未分红，连续3年→ST→*ST"))
            } else if divCount < 3 {
                results.append(("分红不达标", "警示", "仅\(Int(divCount))次分红，缺\(3-Int(divCount))年→ST"))
            } else {
                results.append(("分红不达标", "安全", "累计\(Int(divCount))次，满足要求"))
            }
        } else {
            results.append(("分红不达标", "未知", "需分红数据"))
        }

        // ===== 交易类规则 =====

        // 6. 股价<1元（连续20日 → 直接退市）
        if let price = stock.price, price < 1.0 {
            results.append(("股价<1元", "危险", "连续20日<1元→直接退市（无*ST）"))
        } else if let price = stock.price, price < 2.0 {
            results.append(("股价<1元", "警示", "股价\(String(format: "%.2f", price))，若<1元+20日→退市"))
        } else if let price = stock.price {
            results.append(("股价<1元", "安全", "股价\(String(format: "%.2f", price))，远高于1元红线"))
        } else {
            results.append(("股价<1元", "未知", "需股价数据"))
        }

        // 7. 市值退市（连续20日主板<5亿/创业板科创板<3亿）
        if let cap = stock.total_market_cap {
            let capYi = cap / 100_000_000
            let threshold: Double = {
                if code.hasPrefix("68") || code.hasPrefix("30") { return 3 }
                return 5
            }()
            let boardName = code.hasPrefix("68") ? "科创板" : (code.hasPrefix("30") ? "创业板" : "主板")
            if capYi < threshold {
                results.append(("市值退市", "危险", "连续20日<\(String(format: "%.0f", threshold))亿→直接退市"))
            } else if capYi < threshold * 2 {
                results.append(("市值退市", "警示", "市值\(String(format: "%.1f", capYi))亿，\(boardName)门槛\(String(format: "%.0f", threshold))亿"))
            } else {
                results.append(("市值退市", "安全", "市值\(String(format: "%.1f", capYi))亿，高于\(boardName)\(String(format: "%.0f", threshold))亿门槛"))
            }
        } else {
            results.append(("市值退市", "未知", "需市值数据"))
        }

        // ===== 规范类规则 =====

        // 8. 资金占用（大股东占用>2亿+>30% → *ST）
        if let risk = stock.fund_embezzlement_risk, risk > 0 {
            let ratio = stock.other_receivables_ratio ?? 0
            results.append(("资金占用", "危险", "大股东占用>2亿+占比\(String(format: "%.0f", ratio))%→*ST→退市"))
        } else if let ratio = stock.other_receivables_ratio {
            if ratio > 15 {
                results.append(("资金占用", "警示", "占比\(String(format: "%.0f", ratio))%，若>30%+>2亿→*ST"))
            } else {
                results.append(("资金占用", "安全", "占比\(String(format: "%.0f", ratio))%，低于15%警戒线"))
            }
        } else {
            results.append(("资金占用", "未知", "需资产负债表数据"))
        }
        results.append(("内控失效", "需人工核验", "否定/无法表示意见→*ST→退市"))

        // ===== 重大违法类 =====

        // 10. 财务造假（重大违法 → 直接退市）
        if let risk = stock.financial_fraud_risk, risk >= 2 {
            results.append(("财务造假", "危险", "有造假处罚→重大违法退市"))
        } else if let risk = stock.financial_fraud_risk, risk >= 1 {
            results.append(("财务造假", "警示", "有处罚记录，若重大违法→退市"))
        } else if stock.financial_fraud_risk != nil {
            results.append(("财务造假", "安全", "近3年无处罚记录"))
        } else {
            results.append(("财务造假", "需人工核验", "请查阅证监会处罚公告"))
        }

        return results
    }

    // 检查净利润是否为负
    private func checkProfitNegative() -> Bool {
        guard let yoy = stock.net_profit_yoy else { return false }
        let clean = yoy.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")
        guard let value = Double(clean) else { return false }
        return value < 0
    }

    // 检查营收是否低于门槛
    private func checkRevenueLow(isGEM: Bool, isSTAR: Bool) -> Bool {
        guard let revenue = stock.revenue else { return false }

        // revenue格式可能是 "123.45亿" 或 "1234.56万"
        let numStr = revenue.replacingOccurrences(of: "亿", with: "").replacingOccurrences(of: "万", with: "").replacingOccurrences(of: "元", with: "")
        guard let num = Double(numStr) else { return false }

        var revenueInYuan: Double = num
        if revenue.contains("万") {
            revenueInYuan = num * 10000
        } else if revenue.contains("亿") {
            revenueInYuan = num * 100000000
        }

        // 判断是否低于门槛
        let threshold: Double
        if isSTAR {
            threshold = 50000000  // 5000万
        } else if isGEM {
            threshold = 100000000  // 1亿
        } else {
            threshold = 300000000  // 3亿
        }

        return revenueInYuan < threshold
    }

    private func backgroundColor(for status: String) -> Color {
        switch status {
        case "安全":
            return Color(hex: "4CAF50")
        case "警示":
            return Color(hex: "FFEB3B")
        case "危险":
            return Color(hex: "F44336")
        case "未知":
            return Color(hex: "757575")
        default:
            return Color.gray
        }
    }
}