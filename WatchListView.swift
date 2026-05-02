import SwiftUI

struct WatchListView: View {
    @EnvironmentObject var stockViewModel: StockViewModel
    @State private var selectedCodes: Set<String> = []
    @State private var isSelectionMode = false
    @State private var showBatchBuySheet = false
    @State private var selectedStockIndex: Int = 0
    @State private var showDetailPage = false
    @State private var searchText = ""

    private var filteredFavorites: [Stock] {
        if searchText.isEmpty {
            return stockViewModel.favoritedStocks
        }
        return stockViewModel.favoritedStocks.filter { stock in
            stock.code.localizedCaseInsensitiveContains(searchText) ||
            stock.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedStocks: [Stock] {
        stockViewModel.favoritedStocks.filter { selectedCodes.contains($0.code) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if stockViewModel.favoritedStocks.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("暂无自选股票")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Text("点击股票卡片上的星标添加自选")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 搜索栏
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("搜索股票代码或名称", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.white)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
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

                List {
                    ForEach(Array(filteredFavorites.enumerated()), id: \.element.code) { index, stock in
                        HStack {
                            if isSelectionMode {
                                Button {
                                    if selectedCodes.contains(stock.code) {
                                        selectedCodes.remove(stock.code)
                                    } else {
                                        selectedCodes.insert(stock.code)
                                    }
                                } label: {
                                    Image(systemName: selectedCodes.contains(stock.code) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedCodes.contains(stock.code) ? Color(hex: "1E88E5") : .gray)
                                        .font(.title3)
                                }
                                .padding(.trailing, 8)

                                StockCard(stock: stock, sortOption: .position)
                            } else {
                                Button {
                                    selectedStockIndex = index
                                    showDetailPage = true
                                } label: {
                                    StockCard(stock: stock, sortOption: .position)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .listRowBackground(Color(hex: "1E1E1E"))
                    }
                }
                .listStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
            }
        }
        .background(Color(hex: "121212"))
        .navigationTitle("自选")
        .navigationDestination(isPresented: $showDetailPage) {
            if selectedStockIndex < filteredFavorites.count {
                StockDetailPageView(
                    currentIndex: selectedStockIndex,
                    allStocks: filteredFavorites,
                    currentPage: $selectedStockIndex
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !stockViewModel.favoritedStocks.isEmpty {
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
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode && !selectedCodes.isEmpty {
                VStack(spacing: 8) {
                    HStack {
                        Text("已选 \(selectedCodes.count) 只")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Spacer()
                        Button {
                            showBatchBuySheet = true
                        } label: {
                            Text("批量买入")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color(hex: "4CAF50"))
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .background(Color(hex: "1E1E1E"))
            }
        }
        .sheet(isPresented: $showBatchBuySheet) {
            BatchBuySheetView(
                stocks: selectedStocks,
                isPresented: $showBatchBuySheet,
                onConfirm: { quantities in
                    executeBatchBuy(quantities: quantities)
                    selectedCodes.removeAll()
                    isSelectionMode = false
                }
            )
        }
    }

    private func executeBatchBuy(quantities: [String: String]) {
        for stock in selectedStocks {
            if let price = stock.price, price > 0,
               let qtyStr = quantities[stock.code],
               let qty = Int(qtyStr), qty >= 100, qty % 100 == 0 {
                stockViewModel.buyStock(code: stock.code, name: stock.name, price: price, quantity: qty)
            }
        }
    }
}

// 批量买入弹窗
struct BatchBuySheetView: View {
    let stocks: [Stock]
    @Binding var isPresented: Bool
    let onConfirm: ([String: String]) -> Void

    @State private var quantities: [String: String] = [:]

    var totalAmount: Double {
        stocks.reduce(0) { total, stock in
            if let price = stock.price,
               let qtyStr = quantities[stock.code],
               let qty = Int(qtyStr), qty >= 100, qty % 100 == 0 {
                return total + price * Double(qty)
            }
            return total
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    ForEach(stocks) { stock in
                        VStack(spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stock.name)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text(stock.code)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                if let price = stock.price {
                                    Text("¥\(String(format: "%.2f", price))")
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                }
                            }

                            let qtyBinding = Binding(
                                get: { Int(quantities[stock.code] ?? "100") ?? 100 },
                                set: { newVal in
                                    var copy = quantities
                                    copy[stock.code] = String(newVal)
                                    quantities = copy
                                }
                            )
                            let qty = qtyBinding.wrappedValue
                            let price = stock.price ?? 0
                            let estimatedAmount = price > 0 ? price * Double(qty) : 0

                            HStack(spacing: 8) {
                                // 减号
                                Button {
                                    let newQty = max(100, qty - 100)
                                    qtyBinding.wrappedValue = newQty
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(qty > 100 ? Color(hex: "F44336") : .gray)
                                }
                                .disabled(qty <= 100)

                                // 数量输入
                                TextField("100", text: Binding(
                                    get: { quantities[stock.code] ?? "100" },
                                    set: { newValue in
                                        var copy = quantities
                                        copy[stock.code] = newValue
                                        quantities = copy
                                    }
                                ))
                                .keyboardType(.numberPad)
                                .textFieldStyle(.plain)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .frame(width: 80)

                                // 加号
                                Button {
                                    qtyBinding.wrappedValue = qty + 100
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(Color(hex: "4CAF50"))
                                }

                                Spacer()

                                if estimatedAmount > 0 {
                                    Text("≈ ¥\(String(format: "%.0f", estimatedAmount))")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.plain)
                .listRowBackground(Color(hex: "1E1E1E"))

                // 底部汇总
                VStack(spacing: 8) {
                    HStack {
                        Text("合计金额")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Spacer()
                        Text("¥\(String(format: "%.2f", totalAmount))")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Color(hex: "F44336"))
                    }
                    .padding(.horizontal)

                    Button {
                        onConfirm(quantities)
                        isPresented = false
                    } label: {
                        Text("确认买入")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(hex: "4CAF50"))
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
                .background(Color(hex: "1E1E1E"))
            }
            .background(Color(hex: "121212"))
            .navigationTitle("批量买入")
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
                for stock in stocks {
                    if let price = stock.price, price > 0 {
                        if price >= 100 {
                            dict[stock.code] = "100"
                        } else {
                            let qty = max(100, Int((10000 / price / 100).rounded()) * 100)
                            dict[stock.code] = String(qty)
                        }
                    } else {
                        dict[stock.code] = "100"
                    }
                }
                quantities = dict
            }
        }
    }
}

#Preview {
    NavigationStack {
        WatchListView()
    }
    .environmentObject(StockViewModel())
    .preferredColorScheme(.dark)
}