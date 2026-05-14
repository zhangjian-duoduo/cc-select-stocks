import SwiftUI

enum FinancialSortOption: String, CaseIterable {
    case yoy = "同比"
    case qoq = "环比"
}

struct FinancialUpdatesView: View {
    @EnvironmentObject var stockViewModel: StockViewModel
    @State private var selectedDate: String = ""
    @State private var monthData: [String: Int] = [:]
    @State private var isCalendarExpanded = false
    @State private var currentSort: FinancialSortOption = .yoy
    @State private var sortAscending: Bool = false
    @State private var displayedDate: Date = Date()
    @State private var selectedStockIndex: Int = 0
    @State private var showDetailPage = false

    private let calendar = Calendar.current

    private var currentYearMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: displayedDate)
    }

    private var canGoNext: Bool {
        let now = Date()
        let comps = calendar.dateComponents([.year, .month], from: now)
        let dispComps = calendar.dateComponents([.year, .month], from: displayedDate)
        guard let dispYear = dispComps.year, let dispMonth = dispComps.month,
              let nowYear = comps.year, let nowMonth = comps.month else { return false }
        return dispYear < nowYear || (dispYear == nowYear && dispMonth < nowMonth)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 日历折叠栏
            CalendarMonthPicker(
                displayedDate: $displayedDate,
                selectedDate: $selectedDate,
                isExpanded: $isCalendarExpanded,
                dateData: monthData,
                accentColor: Color(hex: "FFC107"),
                canGoNext: canGoNext,
                onMonthChanged: { loadMonthData(month: $0) },
                onDateSelected: { loadUpdatesForDate(date: $0) }
            )

            // 排序按钮栏
            HStack(spacing: 12) {
                ForEach(FinancialSortOption.allCases, id: \.self) { option in
                    Button {
                        if currentSort == option {
                            sortAscending.toggle()
                        } else {
                            currentSort = option
                            sortAscending = false
                        }
                        reloadWithSort()
                    } label: {
                        HStack(spacing: 4) {
                            Text(option.rawValue)
                                .font(.subheadline)
                                .fontWeight(currentSort == option ? .semibold : .regular)
                            if currentSort == option {
                                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(currentSort == option ? Color(hex: "1E88E5") : Color(hex: "2C2C2C"))
                        .foregroundColor(currentSort == option ? .white : .gray)
                        .cornerRadius(16)
                    }
                }

                Spacer()

                Text("(\(stockViewModel.financialUpdateStocks.count))")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Button {
                    reloadWithSort()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(Color(hex: "1E88E5"))
                }
            }
            .padding()
            .background(Color(hex: "1E1E1E"))

            // 股票列表
            if stockViewModel.isLoadingFinancialUpdates {
                Spacer()
                ProgressView()
                Spacer()
            } else if stockViewModel.financialUpdateStocks.isEmpty {
                Spacer()
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 60))
                        .foregroundColor(Color(hex: "4CAF50"))
                    Text("当日暂无财务数据更新")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                Spacer()
            } else {
                List {
                    ForEach(stockViewModel.financialUpdateStocks) { stock in
                        Button {
                            if let allIdx = stockViewModel.allStocks.firstIndex(where: { $0.code == stock.code }) {
                                selectedStockIndex = allIdx
                                showDetailPage = true
                            }
                        } label: {
                            FinancialUpdateCard(stock: stock)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .listStyle(.plain)
                .listRowBackground(Color(hex: "1E1E1E"))
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .background(Color(hex: "121212"))
        .navigationTitle("财务更新")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showDetailPage) {
            if selectedStockIndex < stockViewModel.allStocks.count {
                StockDetailPageView(
                    currentIndex: selectedStockIndex,
                    allStocks: stockViewModel.allStocks,
                    currentPage: $selectedStockIndex
                )
            }
        }
        .onAppear {
            loadMonthData(month: currentYearMonth)
        }
    }

    private func loadMonthData(month: String) {
        Task {
            do {
                let result: MonthFinancialResponse = try await APIClient.get("/financial_updates/month/\(month)")
                if result.code == 0, let data = result.data {
                    var monthDataDict: [String: Int] = [:]
                    var dateList: [String] = []
                    for item in data.dates {
                        dateList.append(item.date)
                        monthDataDict[item.date] = item.count
                    }
                    let now = Date()
                    let today = String(format: "%04d-%02d-%02d", calendar.component(.year, from: now), calendar.component(.month, from: now), calendar.component(.day, from: now))
                    let dateToSelect: String
                    if dateList.contains(today) {
                        dateToSelect = today
                    } else if let first = dateList.first {
                        dateToSelect = first
                    } else {
                        return
                    }
                    await MainActor.run {
                        monthData = monthDataDict
                        selectedDate = dateToSelect
                    }
                    loadUpdatesForDate(date: dateToSelect)
                }
            } catch {
                print("加载月份数据失败: \(error)")
            }
        }
    }

    private func loadUpdatesForDate(date: String) {
        let sortBy = currentSort == .yoy ? "net_profit_yoy" : "net_profit_qoq"
        let order = sortAscending ? "asc" : "desc"

        Task {
            do {
                let result: FinancialUpdatesResponse = try await APIClient.get("/financial_updates/date/\(date)", queryItems: [URLQueryItem(name: "sort_by", value: sortBy), URLQueryItem(name: "order", value: order)])
                if result.code == 0, let resultData = result.data {
                    await MainActor.run {
                        stockViewModel.financialUpdateStocks = resultData.stocks ?? []
                    }
                }
            } catch {
                print("加载失败: \(error)")
            }
        }
    }

    private func reloadWithSort() {
        let sortBy = currentSort == .yoy ? "net_profit_yoy" : "net_profit_qoq"
        let order = sortAscending ? "asc" : "desc"

        if selectedDate.isEmpty {
            Task {
                do {
                    let result: FinancialUpdatesResponse = try await APIClient.get("/financial_updates", queryItems: [URLQueryItem(name: "sort_by", value: sortBy), URLQueryItem(name: "order", value: order)])
                    if result.code == 0, let resultData = result.data {
                        await MainActor.run {
                            stockViewModel.financialUpdateStocks = resultData.stocks ?? []
                        }
                    }
                } catch {
                    print("刷新失败: \(error)")
                }
            }
        } else {
            loadUpdatesForDate(date: selectedDate)
        }
    }
}

struct FinancialUpdateCard: View {
    let stock: Stock
    @EnvironmentObject var stockViewModel: StockViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    // 检查是否在选股列表中，如果在则显示特殊颜色
                    let stockCodes = stockViewModel.stocks.map { $0.code }
                    let isInWatchlist = stockCodes.contains(stock.code)

                    Text(stock.name.isEmpty ? stock.code : stock.name)
                        .font(.headline)
                        .foregroundColor(isInWatchlist ? Color(hex: "FFC107") : .white)  // 选股列表中的股票用金色
                    Text(stock.code)
                        .font(.caption)
                        .foregroundColor(isInWatchlist ? Color(hex: "FFC107") : .gray)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let price = stock.price {
                        Text(String(format: "¥%.2f", price))
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    if let change = stock.change_pct {
                        Text(String(format: "%+.2f%%", change))
                            .font(.caption)
                            .foregroundColor(change >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                    }
                }
            }

            Divider()
                .background(Color.gray.opacity(0.3))

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("净利润同比")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(stock.net_profit_yoy ?? "-")
                        .font(.subheadline)
                        .foregroundColor(colorForYoy(stock.net_profit_yoy))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("净利润环比")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(stock.net_profit_qoq ?? "-")
                        .font(.subheadline)
                        .foregroundColor(colorForQoq(stock.net_profit_qoq))
                }

                Spacer()

                if let updated = stock.financial_updated_at {
                    Text(updated)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(Color(hex: "1E1E1E"))
        .cornerRadius(12)
    }

    func colorForYoy(_ value: String?) -> Color {
        guard let v = value else { return .gray }
        let clean = v.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")
        guard let num = Double(clean) else { return .gray }
        if num > 0 { return Color(hex: "F44336") }
        else if num < 0 { return Color(hex: "4CAF50") }
        return .gray
    }

    func colorForQoq(_ value: String?) -> Color {
        guard let v = value else { return .gray }
        let clean = v.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")
        guard let num = Double(clean) else { return .gray }
        // 涨=红色，跌=绿色
        if num > 0 { return Color(hex: "F44336") }
        else if num < 0 { return Color(hex: "4CAF50") }
        return .gray
    }
}