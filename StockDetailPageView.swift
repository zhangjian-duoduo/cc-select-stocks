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

                // PE分析
                if let peTTM = detailedStock?.pe_ttm ?? stock.pe_ttm,
                   let pePct = detailedStock?.pe_percentile ?? stock.pe_percentile {
                    PE百分位View(peTTM: peTTM, pePct: pePct)
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
}
