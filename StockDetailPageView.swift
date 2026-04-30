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

    private let baseURL = "http://8.163.91.16:5000/api/v1"

    enum KlinePeriod: String, CaseIterable {
        case daily = "日"
        case weekly = "周"
        case monthly = "月"
    }

    // 打开东方财富App
    func openInEastMoney(code: String) {
        guard code.count == 6 else { return }
        let prefix = code.hasPrefix("6") ? "SH" : "SZ"
        let symbol = "\(prefix)\(code)"

        // 先尝试打开东方财富App
        if let appUrl = URL(string: "eastmoney://quote?symbol=\(symbol)") {
            if UIApplication.shared.canOpenURL(appUrl) {
                UIApplication.shared.open(appUrl)
                return
            }
        }

        // App没安装就用网页版
        let webUrlString = "https://quote.eastmoney.com/\(symbol.lowercased()).html"
        if let webUrl = URL(string: webUrlString) {
            UIApplication.shared.open(webUrl)
        }
    }

    var body: some View {
        TabView(selection: $currentPage) {
            ForEach(Array(allStocks.enumerated()), id: \.offset) { index, stock in
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
                loadStockDetail(code)
            }
            if financialHistoryStocks[code] == nil {
                loadFinancialHistory(code)
            }
        }
    }

    private func loadStockDetail(_ stockCode: String) {
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

    private func loadFinancialHistory(_ stockCode: String) {
        Task {
            guard let url = URL(string: "\(baseURL)/stock/\(stockCode)/financial_history") else { return }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let responseData = json["data"] as? [String: Any],
                       let history = responseData["history"] as? [[String: Any]] {
                        let items = history.compactMap { dict -> Stock.FinancialHistoryItem? in
                            var item = Stock.FinancialHistoryItem()
                            item.report_date = dict["report_date"] as? String
                            item.report_name = dict["report_name"] as? String
                            item.quarter = dict["quarter"] as? String
                            item.net_profit_yoy = dict["net_profit_yoy"] as? String
                            item.net_profit_qoq = dict["net_profit_qoq"] as? String
                            item.revenue_yoy = dict["revenue_yoy"] as? String
                            return item
                        }
                        await MainActor.run {
                            financialHistoryStocks[stockCode] = items
                        }
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
        let code = stock.code ?? ""
        guard code.count == 6 else { return }

        // 市场代码：沪市=1，深市=0
        let marketPrefix = code.hasPrefix("6") || code.hasPrefix("9") || code.hasPrefix("688") ? "1" : "0"
        let secId = "\(marketPrefix).\(code)"

        // 尝试多种URL Scheme格式
        let schemes: [String] = [
            // 使用secid格式（来自东方财富API的格式）
            "eastmoney://quote?secid=\(secId)",
            "eastmoney://quotation?secid=\(secId)",
            "eastmoney://stockdetail?secid=\(secId)",
            "eastmoney://hq?secid=\(secId)",

            // 备用格式
            "eastmoney://stock?secid=\(secId)",
            "emstock://quote?secid=\(secId)"
        ]

        for scheme in schemes {
            if let url = URL(string: scheme) {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                    return
                }
            }
        }

        // 如果App没安装，尝试网页版
        let prefix = code.hasPrefix("6") ? "sh" : "sz"
        let webCode = "\(prefix)\(code)"
        if let webUrl = URL(string: "https://quote.eastmoney.com/\(webCode).html") {
            UIApplication.shared.open(webUrl)
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
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(width: 100, alignment: .trailing)
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
        let isMainBoard = code.hasPrefix("60") || code.hasPrefix("00")
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
            results.append(("净利润+营收(\(revenueThreshold))", "危险", "净利润为负+营收低于门槛"))
        } else if isProfitNegative {
            results.append(("净利润+营收(\(revenueThreshold))", "警示", "净利润为负，需结合营收"))
        } else if let yoy = stock.net_profit_yoy, let yoyVal = Double(yoy), yoyVal >= 0 {
            results.append(("净利润+营收(\(revenueThreshold))", "安全", "净利同比增长\(Int(yoyVal))%"))
        } else if let revenue = stock.revenue {
            results.append(("净利润+营收(\(revenueThreshold))", "安全", "营收\(revenue)"))
        } else {
            results.append(("净利润+营收(\(revenueThreshold))", "未知", "需营收数据"))
        }

        // 2. ROE
        if let roe = stock.roe, let roeVal = Double(roe), roeVal < 0 {
            results.append(("ROE", "警示", "ROE为\(roe)%"))
        } else if let roe = stock.roe, let roeVal = Double(roe), roeVal >= 0 {
            results.append(("ROE", "安全", "ROE为\(roe)%"))
        } else {
            results.append(("ROE", "未知", "缺少数据"))
        }

        // 3. 净资产为负（使用每股净资产判断）
        if let bv = stock.book_value_per_share, let bvVal = Double(bv), bvVal < 0 {
            results.append(("净资产为负", "危险", "每股净资产\(bv)元"))
        } else if let bv = stock.book_value_per_share {
            results.append(("净资产为负", "安全", "每股净资产\(bv)元"))
        } else {
            results.append(("净资产为负", "未知", "需每股净资产"))
        }

        // 4. 审计报告
        results.append(("审计报告非标", "未知", "需审计数据"))

        // 5. 分红不达标
        results.append(("分红不达标", "未知", "需分红数据"))

        // ===== 交易类规则 =====

        // 6. 股价<1元
        if let price = stock.price, price < 1.0 {
            results.append(("股价<1元", "危险", "连续20日退市"))
        } else if let price = stock.price, price < 2.0 {
            results.append(("股价<1元", "警示", "接近红线"))
        } else if let price = stock.price {
            results.append(("股价<1元", "安全", "股价\(String(format: "%.2f", price))"))
        } else {
            results.append(("股价<1元", "未知", "需股价数据"))
        }

        // 7. 市值退市
        results.append(("市值<5亿", "未知", "需市值数据"))

        // ===== 规范类规则 =====

        results.append(("资金占用", "未知", "需资金数据"))
        results.append(("内控失效", "未知", "需内控数据"))

        // ===== 重大违法类 =====

        results.append(("财务造假", "未知", "需调查"))

        return results
    }

    // 检查净利润是否为负
    private func checkProfitNegative() -> Bool {
        if let yoy = stock.net_profit_yoy, let yoyVal = Double(yoy) {
            return yoyVal < 0
        }
        return false
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