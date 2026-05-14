import SwiftUI

struct WatchListView: View {
    @EnvironmentObject var stockViewModel: StockViewModel
    @State private var selectedCodes: Set<String> = []
    @State private var isSelectionMode = false
    @State private var showBatchBuySheet = false
    @State private var selectedStockIndex: Int = 0
    @State private var showDetailPage = false
    @State private var searchText = ""
    @State private var showAddStockSheet = false
    @State private var showNewListAlert = false
    @State private var newListName = ""
    @State private var showRenameAlert = false
    @State private var renameListId = ""
    @State private var renameListName = ""
    @State private var showDeleteAlert = false
    @State private var deleteListId = ""
    @State private var deleteListName = ""
    @State private var longPressListId: String? = nil
    @State private var showManageSheet = false

    private var filteredFavorites: [Stock] {
        let source = stockViewModel.sortedFavoritedStocks
        if searchText.isEmpty {
            return source
        }
        let query = searchText.lowercased()
        return source.filter { stock in
            stock.code.lowercased().contains(query) ||
            stock.name.lowercased().contains(query) ||
            StockViewModel.pinyinInitials(stock.name).contains(query)
        }
    }

    private var selectedStocks: [Stock] {
        stockViewModel.favoritedStocks.filter { selectedCodes.contains($0.code) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 自选列表标签选择器
            watchlistTabSelector

            if stockViewModel.currentWatchlistCodes.isEmpty {
                emptyContentView
            } else {
                // 搜索栏
                searchBar

                // 排序选择器
                sortPicker

                // 股票列表
                stockList
            }
        }
        .background(Color(hex: "121212"))
        .navigationTitle("自选")
        .navigationBarTitleDisplayMode(.inline)
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
            ToolbarItem(placement: .navigationBarLeading) {
                if !stockViewModel.currentWatchlistCodes.isEmpty {
                    if isSelectionMode {
                        Button("全选") {
                            selectedCodes = Set(filteredFavorites.map { $0.code })
                        }
                        .foregroundColor(Color(hex: "1E88E5"))
                    } else {
                        Button {
                            showAddStockSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.subheadline)
                                Text("添加股票")
                                    .font(.subheadline)
                            }
                            .foregroundColor(Color(hex: "1E88E5"))
                        }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !stockViewModel.currentWatchlistCodes.isEmpty {
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
                batchBuyBar
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
        .sheet(isPresented: $showAddStockSheet) {
            AddStockSheetView(isPresented: $showAddStockSheet)
        }
        // 新建列表 Alert
        .alert("新建自选列表", isPresented: $showNewListAlert) {
            TextField("列表名称", text: $newListName)
            Button("取消", role: .cancel) {
                newListName = ""
            }
            Button("创建") {
                let name = newListName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    stockViewModel.createWatchlist(name: name)
                }
                newListName = ""
            }
        } message: {
            Text("输入新自选列表的名称")
        }
        // 重命名 Alert
        .alert("重命名列表", isPresented: $showRenameAlert) {
            TextField("列表名称", text: $renameListName)
            Button("取消", role: .cancel) {
                renameListName = ""
            }
            Button("确认") {
                let name = renameListName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    stockViewModel.renameWatchlist(id: renameListId, name: name)
                }
                renameListName = ""
            }
        } message: {
            Text("修改自选列表的名称")
        }
        // 删除确认 Alert
        .alert("删除列表", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                stockViewModel.deleteWatchlist(id: deleteListId)
            }
        } message: {
            Text("确定要删除「\(deleteListName)」吗？列表中的股票不会被删除。")
        }
    }

    // MARK: - 自选列表标签选择器

    private var watchlistTabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(stockViewModel.watchlists) { list in
                    let isSelected = list.id == (stockViewModel.currentWatchlist?.id ?? "")
                    Button {
                        stockViewModel.selectWatchlist(id: list.id)
                    } label: {
                        Text(list.name)
                            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .white : .gray)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color(hex: "1E88E5") : Color(hex: "2C2C2C"))
                            .cornerRadius(16)
                    }
                    .onLongPressGesture {
                        renameListId = list.id
                        renameListName = list.name
                        showManageSheet = true
                    }
                    .confirmationDialog("管理列表", isPresented: $showManageSheet, titleVisibility: .visible) {
                        Button("重命名") {
                            showRenameAlert = true
                        }
                        Button("删除列表", role: .destructive) {
                            deleteListId = renameListId
                            deleteListName = renameListName
                            showDeleteAlert = true
                        }
                        Button("取消", role: .cancel) {}
                    }
                }

                // 新建列表按钮
                Button {
                    newListName = ""
                    showNewListAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "1E88E5"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(hex: "2C2C2C"))
                        .cornerRadius(16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(hex: "1A1A1A"))
    }

    // MARK: - 空列表视图

    private var emptyContentView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "star.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("暂无自选股票")
                .font(.headline)
                .foregroundColor(.gray)
            Text("点击下方按钮添加 A 股股票")
                .font(.subheadline)
                .foregroundColor(.gray)

            Button {
                showAddStockSheet = true
            } label: {
                Label("添加股票", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color(hex: "1E88E5"))
                    .cornerRadius(10)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
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
    }

    // MARK: - 排序选择器

    private var sortPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button {
                        if stockViewModel.watchlistSortOption == option {
                            stockViewModel.watchlistSortAscending.toggle()
                        } else {
                            stockViewModel.watchlistSortOption = option
                            stockViewModel.watchlistSortAscending = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(option.rawValue)
                            if stockViewModel.watchlistSortOption == option {
                                Image(systemName: stockViewModel.watchlistSortAscending ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .font(.caption)
                        .foregroundColor(stockViewModel.watchlistSortOption == option ? .white : .gray)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(stockViewModel.watchlistSortOption == option ? Color(hex: "1E88E5") : Color(hex: "2C2C2C"))
                        .cornerRadius(14)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 4)
    }

    // MARK: - 股票列表

    private var stockList: some View {
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
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        stockViewModel.removeFromFavorites(stock.code)
                    } label: {
                        Label("移除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .refreshable {
            stockViewModel.refreshLivePrices()
        }
    }

    // MARK: - 批量买入栏

    private var batchBuyBar: some View {
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

    // MARK: - Helpers

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

// MARK: - 添加股票搜索 Sheet

struct AddStockSheetView: View {
    @EnvironmentObject var stockViewModel: StockViewModel
    @Binding var isPresented: Bool
    @State private var searchQuery = ""
    @State private var searchResults: [Stock] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索栏
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("输入代码、名称或拼音搜索 A 股", text: $searchQuery)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.white)
                        .onChange(of: searchQuery) { _ in
                            performSearch()
                        }
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                            searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(10)
                .background(Color(hex: "2C2C2C"))
                .cornerRadius(10)
                .padding(12)

                if isSearching {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .tint(.gray)
                    Spacer()
                } else if searchResults.isEmpty && !searchQuery.isEmpty {
                    Spacer()
                    if let error = searchError {
                        VStack(spacing: 8) {
                            Text("搜索失败")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    } else {
                        Text("未找到匹配的股票")
                            .foregroundColor(.gray)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(searchResults) { stock in
                            let isInList = stockViewModel.currentWatchlistCodes.contains(stock.code)
                            Button {
                                if isInList {
                                    stockViewModel.removeFromFavorites(stock.code)
                                } else {
                                    stockViewModel.addToFavorites(stock)
                                }
                            } label: {
                                HStack(spacing: 0) {
                                    Image(systemName: isInList ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(isInList ? Color(hex: "4CAF50") : .gray)
                                        .font(.title3)
                                        .frame(width: 32)

                                    StockCard(stock: stock, sortOption: .position)
                                        .allowsHitTesting(false)
                                }
                            }
                            .listRowBackground(Color(hex: "1E1E1E"))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color(hex: "121212"))
            .navigationTitle("添加股票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        isPresented = false
                    }
                }
            }
        }
    }

    private func performSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, q.count >= 1 else {
            searchResults = []
            searchError = nil
            return
        }

        // Debounce: 取消上一次未完成的搜索任务
        searchTask?.cancel()
        let currentQuery = q
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard currentQuery == searchQuery.trimmingCharacters(in: .whitespaces) else { return }

            await MainActor.run { isSearching = true; searchError = nil }

            do {
                let result: StockResponse = try await APIClient.get(
                    "/search_stocks",
                    queryItems: [URLQueryItem(name: "q", value: currentQuery)],
                    retries: 1,
                    timeout: 10
                )
                await MainActor.run {
                    if result.code == 0 {
                        searchResults = result.data ?? []
                    } else {
                        searchResults = []
                        searchError = result.message ?? "搜索失败"
                    }
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                    searchError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - 批量买入弹窗

struct BatchBuySheetView: View {
    let stocks: [Stock]
    @Binding var isPresented: Bool
    let onConfirm: ([String: String]) -> Void

    @State private var quantities: [String: String] = [:]
    @State private var errorMessage: String?

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
                                Button {
                                    let newQty = max(100, qty - 100)
                                    qtyBinding.wrappedValue = newQty
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(qty > 100 ? Color(hex: "F44336") : .gray)
                                }
                                .disabled(qty <= 100)

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

                VStack(spacing: 8) {
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(Color(hex: "FF9800"))
                            .padding(.horizontal)
                    }

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
                        errorMessage = nil
                        var hasError = false
                        for stock in stocks {
                            let qtyStr = quantities[stock.code] ?? ""
                            guard let qty = Int(qtyStr) else {
                                errorMessage = "\(stock.name): 请输入有效数字"
                                hasError = true; break
                            }
                            guard qty >= 100, qty % 100 == 0 else {
                                errorMessage = "\(stock.name): 数量须为100的整数倍"
                                hasError = true; break
                            }
                        }
                        if !hasError {
                            onConfirm(quantities)
                            isPresented = false
                        }
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
