import SwiftUI

struct PortfolioView: View {
    @EnvironmentObject var stockViewModel: StockViewModel
    @State private var showSellSheet = false
    @State private var selectedPosition: Position?
    @State private var sellQuantity = ""
    @State private var isSelectionMode = false
    @State private var selectedCodes: Set<String> = []
    @State private var showBatchBuySheet = false
    @State private var showAddStockSheet = false
    @State private var showBatchSellSheet = false
    @State private var showTradeHistory = false
    @State private var displayMode: PositionDisplayMode = .marketValue
    @State private var sortAscending = false
    @State private var searchText = ""
    @State private var showCapitalAlert = false
    @State private var capitalInput = ""

    enum PositionDisplayMode: String, CaseIterable {
        case marketValue = "股票/市值"
        case priceCost = "现价/成本"
        case posReturn = "持仓盈亏"
        case dailyReturn = "当日盈亏"
    }

    private func currentPrice(for position: Position) -> Double {
        stockViewModel.latestPrice(for: position.code) ?? position.currentPrice
    }

    struct DisplayPosition: Identifiable {
        let position: Position
        let marketValue: Double
        let posReturn: Double
        let posReturnPct: Double
        let dailyReturn: Double
        let currentPrice: Double
        var id: String { position.id }
    }

    private var filteredPositions: [Position] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return stockViewModel.positionList }
        return stockViewModel.positionList.filter { pos in
            pos.name.lowercased().contains(q) ||
            pos.code.lowercased().contains(q) ||
            StockViewModel.pinyinInitials(pos.name).contains(q)
        }
    }

    @State private var displayData: [DisplayPosition] = []

    private func rebuildDisplayData() {
        displayData = buildDisplayPositions(sortBy: displayMode)
    }

    private func buildDisplayPositions(sortBy mode: PositionDisplayMode) -> [DisplayPosition] {
        filteredPositions.map { pos in
            let price = currentPrice(for: pos)
            let mktVal = price * Double(pos.quantity)
            let posRet = (price - pos.avgCost) * Double(pos.quantity)
            let posRetPct = pos.avgCost > 0 ? (price - pos.avgCost) / pos.avgCost * 100 : 0
            let dailyPct = stockViewModel.latestChangePct(for: pos.code) ?? 0
            let yesterdayPrice = dailyPct != -100 ? price / (1 + dailyPct / 100) : price
            let dailyRet = (price - yesterdayPrice) * Double(pos.quantity)
            return DisplayPosition(position: pos, marketValue: mktVal, posReturn: posRet, posReturnPct: posRetPct, dailyReturn: dailyRet, currentPrice: price)
        }.sorted { a, b in
            let result: Bool
            switch mode {
            case .marketValue: result = a.marketValue > b.marketValue
            case .priceCost: result = a.currentPrice > b.currentPrice
            case .posReturn: result = a.posReturn > b.posReturn
            case .dailyReturn: result = a.dailyReturn > b.dailyReturn
            }
            return sortAscending ? !result : result
        }
    }

    private var selectedPositions: [Position] {
        stockViewModel.positionList.filter { selectedCodes.contains($0.code) }
    }

    private var selectedStocks: [Stock] {
        selectedPositions.compactMap { pos in
            guard var stock = stockViewModel.allStocksDict[pos.code] else {
                return nil
            }
            if let live = stockViewModel.livePrices[pos.code] {
                stock.price = live.price
                stock.change_pct = live.changePct
            }
            return stock
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if stockViewModel.positionList.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("暂无持仓")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Text("在股票详情页点击买入添加持仓")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Button {
                        showAddStockSheet = true
                    } label: {
                        Label("搜索添加股票", systemImage: "plus.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color(hex: "1E88E5"))
                            .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 总持仓统计
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        // 持仓
                        VStack(alignment: .leading, spacing: 4) {
                            Text("持仓")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("¥\(String(format: "%.2f", stockViewModel.totalMarketValue))")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                            .frame(height: 40)
                            .background(Color.gray.opacity(0.3))
                        // 总成本
                        VStack(alignment: .leading, spacing: 4) {
                            Text("总成本")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("¥\(String(format: "%.2f", stockViewModel.totalCost))")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    Divider().background(Color.gray.opacity(0.2))

                    HStack(spacing: 0) {
                        // 当日盈亏
                        VStack(alignment: .leading, spacing: 4) {
                            Text("当日盈亏")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(String(format: "%@%.2f", stockViewModel.totalDailyReturn >= 0 ? "+" : "", stockViewModel.totalDailyReturn))
                                .font(.headline)
                                .foregroundColor(stockViewModel.totalDailyReturn >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                            .frame(height: 40)
                            .background(Color.gray.opacity(0.3))
                        // 总盈亏
                        VStack(alignment: .leading, spacing: 4) {
                            Text("总盈亏")
                                .font(.caption)
                                .foregroundColor(.gray)
                            HStack(spacing: 2) {
                                Text(String(format: "%@%.2f", stockViewModel.totalReturn >= 0 ? "+" : "", stockViewModel.totalReturn))
                                    .font(.headline)
                                    .foregroundColor(stockViewModel.totalReturn >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                                Text(String(format: "(%@%.1f%%)", stockViewModel.totalReturnPct >= 0 ? "+" : "", stockViewModel.totalReturnPct))
                                    .font(.caption2)
                                    .foregroundColor(stockViewModel.totalReturnPct >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .frame(maxWidth: .infinity)
                .background(Color(hex: "1E1E1E"))

                // 现金余额
                Button {
                    capitalInput = String(format: "%.0f", stockViewModel.initialCapital)
                    showCapitalAlert = true
                } label: {
                    HStack {
                        Text("现金余额")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.gray.opacity(0.5))
                        Spacer()
                        Text("¥\(String(format: "%.2f", stockViewModel.cashBalance))")
                            .font(.caption)
                            .foregroundColor(.white)
                        Text("|")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("总资产")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("¥\(String(format: "%.2f", stockViewModel.netWorth))")
                            .font(.caption)
                            .foregroundColor(.white)
                        let allTimeSign = stockViewModel.totalReturnAllTime >= 0 ? "+" : ""
                        Text("(\(allTimeSign)\(String(format: "%.1f", stockViewModel.totalReturnAllTimePct))%)")
                            .font(.caption2)
                            .foregroundColor(stockViewModel.totalReturnAllTime >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: "252525"))


                // 搜索栏
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    TextField("搜索代码或名称", text: $searchText)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(6)
                .background(Color(hex: "2C2C2C"))
                .cornerRadius(6)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                // 列排序头
                HStack(spacing: 0) {
                    ForEach(PositionDisplayMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if displayMode == mode {
                                    sortAscending.toggle()
                                } else {
                                    displayMode = mode
                                    sortAscending = false
                                }
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Text(mode.rawValue)
                                    .font(.system(size: 11))
                                if displayMode == mode {
                                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 8))
                                }
                            }
                            .foregroundColor(displayMode == mode ? .white : .gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(displayMode == mode ? Color(hex: "1E88E5").opacity(0.3) : Color.clear)
                            .cornerRadius(3)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(hex: "1E1E1E"))

                List {
                    ForEach(displayData) { dp in
                        HStack(spacing: 0) {
                            if isSelectionMode {
                                Button {
                                    if selectedCodes.contains(dp.position.code) {
                                        selectedCodes.remove(dp.position.code)
                                    } else {
                                        selectedCodes.insert(dp.position.code)
                                    }
                                } label: {
                                    Image(systemName: selectedCodes.contains(dp.position.code) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedCodes.contains(dp.position.code) ? Color(hex: "1E88E5") : .gray)
                                        .font(.system(size: 14))
                                }
                                .padding(.trailing, 4)
                            }

                            // 列1: 股票/市值
                            VStack(alignment: .leading, spacing: 1) {
                                Text(dp.position.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text("¥\(String(format: "%.0f", dp.marketValue))")
                                    .font(.system(size: 9))
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            // 列2: 现价/成本
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("¥\(String(format: "%.2f", dp.currentPrice))")
                                    .font(.system(size: 11))
                                    .foregroundColor(displayMode == .priceCost ? .white : .gray)
                                Text("¥\(String(format: "%.2f", dp.position.avgCost))")
                                    .font(.system(size: 9))
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)

                            // 列3: 持仓盈亏
                            let posSign = dp.posReturn >= 0 ? "+" : ""
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(posSign)¥\(String(format: "%.0f", dp.posReturn))")
                                    .font(.system(size: 11))
                                    .foregroundColor(displayMode == .posReturn ? .white : (dp.posReturn >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50")))
                                Text("\(posSign)\(String(format: "%.1f", dp.posReturnPct))%")
                                    .font(.system(size: 9))
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)

                            // 列4: 当日盈亏
                            let daySign = dp.dailyReturn >= 0 ? "+" : ""
                            Text("\(daySign)¥\(String(format: "%.0f", dp.dailyReturn))")
                                .font(.system(size: 11))
                                .foregroundColor(displayMode == .dailyReturn ? .white : (dp.dailyReturn >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50")))
                                .frame(maxWidth: .infinity, alignment: .trailing)

                            if !isSelectionMode {
                                Button {
                                    showSellSheet = true
                                    selectedPosition = dp.position
                                } label: {
                                    Text("卖")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(hex: "F44336"))
                                        .cornerRadius(3)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowBackground(Color(hex: "1E1E1E"))
                    }
                }
                .listStyle(.plain)
                .listRowSpacing(0)
                .refreshable {
                    stockViewModel.refreshLivePrices()
                    stockViewModel.updatePositionPrices()
                }
            }
        }
        .background(Color(hex: "121212"))
        .navigationTitle("持仓")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isSelectionMode {
                    Button("全选") {
                        selectedCodes = Set(stockViewModel.positionList.map { $0.code })
                    }
                    .foregroundColor(Color(hex: "1E88E5"))
                } else {
                    Button {
                        showTradeHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(Color(hex: "1E88E5"))
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !stockViewModel.positionList.isEmpty {
                    Button(isSelectionMode ? "取消" : "选择") {
                        isSelectionMode.toggle()
                        if !isSelectionMode {
                            selectedCodes.removeAll()
                        }
                    }
                    .foregroundColor(Color(hex: "1E88E5"))
                }
            }
        }
        .sheet(isPresented: $showTradeHistory) {
            TradeHistoryView(trades: stockViewModel.trades.reversed())
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode && !selectedCodes.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Text("已选 \(selectedCodes.count) 只")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Spacer()
                        Button {
                            showBatchBuySheet = true
                        } label: {
                            Text("批量买入")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(hex: "4CAF50"))
                                .cornerRadius(8)
                        }
                        Button {
                            showBatchSellSheet = true
                        } label: {
                            Text("批量卖出")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(hex: "F44336"))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .background(Color(hex: "1E1E1E"))
            }
        }
        .onAppear {
            stockViewModel.updatePositionPrices()
            rebuildDisplayData()
        }
        .onChange(of: displayMode) { _ in
            rebuildDisplayData()
        }
        .onChange(of: sortAscending) { _ in
            rebuildDisplayData()
        }
        .onChange(of: searchText) { _ in
            rebuildDisplayData()
        }
        .onReceive(stockViewModel.$livePrices) { _ in
            rebuildDisplayData()
        }
        .sheet(isPresented: $showSellSheet) {
            if let position = selectedPosition {
                SellSheetView(
                    position: position,
                    isPresented: $showSellSheet,
                    quantity: $sellQuantity
                )
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showBatchBuySheet) {
            BatchBuySheetView(
                stocks: selectedStocks,
                isPresented: $showBatchBuySheet,
                onConfirm: { quantities in
                    for stock in selectedStocks {
                        if let price = stock.price, price > 0,
                           let qtyStr = quantities[stock.code],
                           let qty = Int(qtyStr), qty >= 100, qty % 100 == 0 {
                            stockViewModel.buyStock(code: stock.code, name: stock.name, price: price, quantity: qty)
                        }
                    }
                    selectedCodes.removeAll()
                    isSelectionMode = false
                }
            )
        }
        .sheet(isPresented: $showBatchSellSheet) {
            BatchSellSheetView(
                positions: selectedPositions,
                currentPrice: { pos in
                    stockViewModel.latestPrice(for: pos.code) ?? pos.currentPrice
                },
                isPresented: $showBatchSellSheet,
                onConfirm: { quantities in
                    for position in selectedPositions {
                        if let qtyStr = quantities[position.code],
                           let qty = Int(qtyStr), qty >= 100, qty % 100 == 0 {
                            let price = currentPrice(for: position)
                            if qty >= position.quantity {
                                _ = stockViewModel.sellStock(code: position.code, price: price, quantity: position.quantity)
                            } else {
                                _ = stockViewModel.sellStock(code: position.code, price: price, quantity: qty)
                            }
                        }
                    }
                    selectedCodes.removeAll()
                    isSelectionMode = false
                }
            )
        }
        .sheet(isPresented: $showAddStockSheet) {
            AddStockSheetView(isPresented: $showAddStockSheet)
        }
        .alert("设置初始资金", isPresented: $showCapitalAlert) {
            TextField("金额", text: $capitalInput)
                .keyboardType(.numberPad)
            Button("确定") {
                if let value = Double(capitalInput), value > 0 {
                    stockViewModel.initialCapital = value
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("模拟交易的起始资金，已发生的交易不会回溯调整")
        }
    }
}

// 批量卖出弹窗
struct BatchSellSheetView: View {
    let positions: [Position]
    let currentPrice: (Position) -> Double
    @Binding var isPresented: Bool
    let onConfirm: ([String: String]) -> Void

    @State private var quantities: [String: String] = [:]
    @State private var errorMessage: String?

    var totalAmount: Double {
        positions.reduce(0) { total, pos in
            if let qtyStr = quantities[pos.code],
               let qty = Int(qtyStr), qty >= 100, qty % 100 == 0 {
                return total + currentPrice(pos) * Double(min(qty, pos.quantity))
            }
            return total
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 全局快捷选择
                HStack(spacing: 8) {
                    Text("全部设为:")
                        .font(.caption)
                        .foregroundColor(.gray)
                    ForEach(["1/4", "1/3", "1/2", "全仓"], id: \.self) { label in
                        Button {
                            errorMessage = nil
                            var copy = quantities
                            for pos in positions {
                                let targetQty: Int
                                switch label {
                                case "1/4": targetQty = pos.quantity / 4
                                case "1/3": targetQty = pos.quantity / 3
                                case "1/2": targetQty = pos.quantity / 2
                                default: targetQty = pos.quantity
                                }
                                copy[pos.code] = String(max(100, (targetQty / 100) * 100))
                            }
                            quantities = copy
                        } label: {
                            Text(label)
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(hex: "1E88E5"))
                                .cornerRadius(4)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(hex: "1E1E1E"))

                List {
                    ForEach(positions) { position in
                        VStack(spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(position.name)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text(position.code)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("持仓 \(position.quantity)股")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Text("¥\(String(format: "%.2f", currentPrice(position)))")
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                }
                            }

                            let qtyBinding = Binding(
                                get: { Int(quantities[position.code] ?? String(position.quantity)) ?? position.quantity },
                                set: { newVal in
                                    var copy = quantities
                                    copy[position.code] = String(newVal)
                                    quantities = copy
                                }
                            )
                            let qty = min(qtyBinding.wrappedValue, position.quantity)

                            HStack(spacing: 8) {
                                Button {
                                    qtyBinding.wrappedValue = max(100, qty - 100)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(qty > 100 ? Color(hex: "F44336") : .gray)
                                }
                                .disabled(qty <= 100)

                                TextField("100", text: Binding(
                                    get: { quantities[position.code] ?? String(position.quantity) },
                                    set: { newValue in
                                        var copy = quantities
                                        copy[position.code] = newValue
                                        quantities = copy
                                    }
                                ))
                                .keyboardType(.numberPad)
                                .textFieldStyle(.plain)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .frame(width: 80)

                                Button {
                                    qtyBinding.wrappedValue = min(qty + 100, position.quantity)
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(qty < position.quantity ? Color(hex: "4CAF50") : .gray)
                                }
                                .disabled(qty >= position.quantity)

                                Spacer()

                                Text("≈ ¥\(String(format: "%.0f", currentPrice(position) * Double(qty)))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }

                            // 个股快捷选择
                            HStack(spacing: 8) {
                                ForEach([
                                    ("1/4", position.quantity / 4),
                                    ("1/3", position.quantity / 3),
                                    ("1/2", position.quantity / 2),
                                    ("全仓", position.quantity)
                                ], id: \.0) { label, targetQty in
                                    let rounded = max(100, (targetQty / 100) * 100)
                                    Button {
                                        var copy = quantities
                                        copy[position.code] = String(rounded)
                                        quantities = copy
                                    } label: {
                                        Text(label)
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color(hex: "2C2C2C"))
                                            .cornerRadius(4)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.plain)
                .listRowBackground(Color(hex: "1E1E1E"))

                VStack(spacing: 8) {
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(Color(hex: "FF9800"))
                            .padding(.horizontal)
                    }

                    HStack {
                        Text("预计回收金额")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Spacer()
                        Text("¥\(String(format: "%.2f", totalAmount))")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Color(hex: "4CAF50"))
                    }
                    .padding(.horizontal)

                    Button {
                        errorMessage = nil
                        var hasError = false
                        for pos in positions {
                            let qtyStr = quantities[pos.code] ?? ""
                            guard let qty = Int(qtyStr) else {
                                errorMessage = "\(pos.name): 请输入有效数字"
                                hasError = true; break
                            }
                            guard qty >= 100, qty % 100 == 0 else {
                                errorMessage = "\(pos.name): 数量须为100的整数倍"
                                hasError = true; break
                            }
                            guard qty <= pos.quantity else {
                                errorMessage = "\(pos.name): 超出持仓(\(pos.quantity)股)"
                                hasError = true; break
                            }
                        }
                        if !hasError {
                            onConfirm(quantities)
                            isPresented = false
                        }
                    } label: {
                        Text("确认卖出")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(hex: "F44336"))
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
                .background(Color(hex: "1E1E1E"))
            }
            .background(Color(hex: "121212"))
            .navigationTitle("批量卖出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        isPresented = false
                    }
                }
            }
            .onAppear {
                var dict: [String: String] = [:]
                for pos in positions {
                    dict[pos.code] = String(pos.quantity)
                }
                quantities = dict
            }
        }
    }
}

// 交易记录视图
struct TradeHistoryView: View {
    let trades: [Trade]
    @EnvironmentObject var stockViewModel: StockViewModel
    @State private var isSelectionMode = false
    @State private var selectedIds: Set<String> = []
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    if trades.isEmpty {
                        Text("暂无交易记录")
                            .foregroundColor(.gray)
                            .listRowBackground(Color(hex: "1E1E1E"))
                    } else {
                        ForEach(trades) { trade in
                            HStack {
                                if isSelectionMode {
                                    Button {
                                        if selectedIds.contains(trade.id) {
                                            selectedIds.remove(trade.id)
                                        } else {
                                            selectedIds.insert(trade.id)
                                        }
                                    } label: {
                                        Image(systemName: selectedIds.contains(trade.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedIds.contains(trade.id) ? Color(hex: "1E88E5") : .gray)
                                            .font(.system(size: 16))
                                    }
                                    .padding(.trailing, 6)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(trade.name)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text(trade.code)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(trade.isBuy ? "买入" : "卖出")
                                        .font(.caption)
                                        .foregroundColor(trade.isBuy ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                                    Text("\(trade.quantity)股 @ ¥\(String(format: "%.2f", trade.price))")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    if !trade.isBuy, let pos = stockViewModel.positions[trade.code] {
                                        let pnl = (trade.price - pos.avgCost) * Double(trade.quantity)
                                        let sign = pnl >= 0 ? "+" : ""
                                        Text("盈亏: \(sign)¥\(String(format: "%.2f", pnl))")
                                            .font(.caption2)
                                            .foregroundColor(pnl >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                                    }
                                    Text(trade.date, style: .date)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color(hex: "1E1E1E"))
                        }
                    }
                }
                .listStyle(.plain)
                .background(Color(hex: "121212"))

                // 删除按钮
                if isSelectionMode && !selectedIds.isEmpty {
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Text("删除选中 (\(selectedIds.count))")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color(hex: "F44336"))
                            .cornerRadius(10)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .background(Color(hex: "121212"))
            .navigationTitle("交易记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isSelectionMode {
                        Button("全选") {
                            selectedIds = Set(trades.map { $0.id })
                        }
                        .foregroundColor(Color(hex: "1E88E5"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !trades.isEmpty {
                        Button(isSelectionMode ? "取消" : "选择") {
                            isSelectionMode.toggle()
                            if !isSelectionMode {
                                selectedIds.removeAll()
                            }
                        }
                        .foregroundColor(Color(hex: "1E88E5"))
                    }
                }
            }
            .alert("确认删除", isPresented: $showDeleteConfirm) {
                Button("删除", role: .destructive) {
                    stockViewModel.deleteTrades(ids: selectedIds)
                    selectedIds.removeAll()
                    isSelectionMode = false
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将删除 \(selectedIds.count) 条交易记录，此操作不可撤销")
            }
        }
    }
}

#Preview {
    NavigationStack {
        PortfolioView()
    }
    .environmentObject(StockViewModel())
    .preferredColorScheme(.dark)
}
