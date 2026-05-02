import SwiftUI

struct PortfolioView: View {
    @EnvironmentObject var stockViewModel: StockViewModel
    @State private var showSellSheet = false
    @State private var selectedPosition: Position?
    @State private var sellQuantity = ""
    @State private var isSelectionMode = false
    @State private var selectedCodes: Set<String> = []
    @State private var showBatchBuySheet = false
    @State private var showBatchSellSheet = false
    @State private var showTradeHistory = false

    private func currentPrice(for position: Position) -> Double {
        stockViewModel.allStocks.first(where: { $0.code == position.code })?.price ?? position.currentPrice
    }

    private var totalMarketValue: Double {
        stockViewModel.positionList.reduce(0) {
            $0 + currentPrice(for: $1) * Double($1.quantity)
        }
    }

    private var selectedPositions: [Position] {
        stockViewModel.positionList.filter { selectedCodes.contains($0.code) }
    }

    private var selectedStocks: [Stock] {
        selectedPositions.compactMap { pos in
            if let stock = stockViewModel.allStocks.first(where: { $0.code == pos.code }) {
                return stock
            }
            return nil
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 总持仓统计
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("总市值")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Text("¥\(String(format: "%.2f", totalMarketValue))")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("总盈亏")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            HStack {
                                Text(String(format: "%@¥%.2f", stockViewModel.totalReturn >= 0 ? "+" : "", stockViewModel.totalReturn))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(stockViewModel.totalReturn >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                                Text("(\(String(format: "%@%.1f%%", stockViewModel.totalReturnPct >= 0 ? "+" : "", stockViewModel.totalReturnPct)))")
                                    .font(.subheadline)
                                    .foregroundColor(stockViewModel.totalReturnPct >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(hex: "1E1E1E"))

                List {
                    ForEach(stockViewModel.positionList) { position in
                        HStack {
                            if isSelectionMode {
                                Button {
                                    if selectedCodes.contains(position.code) {
                                        selectedCodes.remove(position.code)
                                    } else {
                                        selectedCodes.insert(position.code)
                                    }
                                } label: {
                                    Image(systemName: selectedCodes.contains(position.code) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedCodes.contains(position.code) ? Color(hex: "1E88E5") : .gray)
                                        .font(.title3)
                                }
                                .padding(.trailing, 8)
                            }

                            VStack(alignment: .leading, spacing: 8) {
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
                                    if !isSelectionMode {
                                        Button {
                                            showSellSheet = true
                                            selectedPosition = position
                                        } label: {
                                            Text("卖出")
                                                .font(.caption)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color(hex: "F44336"))
                                                .cornerRadius(6)
                                        }
                                    }
                                }

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(position.quantity)股")
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                        Text("¥\(String(format: "%.2f", currentPrice(for: position)))")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("成本: ¥\(String(format: "%.2f", position.avgCost))")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        HStack(spacing: 4) {
                                            let rtn = position.realTimeReturnPct(currentPrice(for: position))
                                            Text("盈亏:")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                            Text(String(format: "%@%.1f%%", rtn >= 0 ? "+" : "", rtn))
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(rtn >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.plain)
                .listRowBackground(Color(hex: "1E1E1E"))
            }
        }
        .background(Color(hex: "121212"))
        .navigationTitle("持仓")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showTradeHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(Color(hex: "1E88E5"))
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
        }
        .sheet(isPresented: $showSellSheet) {
            if let position = selectedPosition {
                SellSheetView(
                    position: position,
                    isPresented: $showSellSheet,
                    quantity: $sellQuantity
                )
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
                    stockViewModel.allStocks.first(where: { $0.code == pos.code })?.price ?? pos.currentPrice
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

    var body: some View {
        NavigationStack {
            List {
                if trades.isEmpty {
                    Text("暂无交易记录")
                        .foregroundColor(.gray)
                        .listRowBackground(Color(hex: "1E1E1E"))
                } else {
                    ForEach(trades) { trade in
                        HStack {
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
            .navigationTitle("交易记录")
            .navigationBarTitleDisplayMode(.inline)
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
