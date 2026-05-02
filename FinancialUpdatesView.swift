import SwiftUI

enum FinancialSortOption: String, CaseIterable {
    case yoy = "同比"
    case qoq = "环比"
}

struct FinancialUpdatesView: View {
    @EnvironmentObject var stockViewModel: StockViewModel
    @State private var selectedDate: String = ""
    @State private var monthData: [String: Int] = [:]
    @State private var datesWithData: [String] = []
    @State private var isCalendarExpanded = false
    @State private var currentSort: FinancialSortOption = .yoy
    @State private var sortAscending: Bool = false
    @State private var displayedDate: Date = Date()

    private let baseURL = "http://8.163.91.16:5000/api/v1"

    private let calendar = Calendar.current

    private var currentYearMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: displayedDate)
    }

    private var currentYear: Int {
        calendar.component(.year, from: displayedDate)
    }

    private var currentMonth: Int {
        calendar.component(.month, from: displayedDate)
    }

    private var canGoNext: Bool {
        let now = Date()
        let comps = calendar.dateComponents([.year, .month], from: now)
        let dispComps = calendar.dateComponents([.year, .month], from: displayedDate)
        return dispComps.year! < comps.year! || (dispComps.year! == comps.year! && dispComps.month! < comps.month!)
    }

    private var daysOfMonth: [Int] {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = currentYear
        components.month = currentMonth
        components.day = 1
        if let date = calendar.date(from: components),
           let range = calendar.range(of: .day, in: .month, for: date) {
            return Array(range)
        }
        return []
    }

    private var firstWeekdayOffset: Int {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = currentYear
        components.month = currentMonth
        components.day = 1
        let firstDayOfMonth = calendar.date(from: components) ?? Date()
        let weekday = calendar.component(.weekday, from: firstDayOfMonth)
        return weekday - 1
    }

    private func makeDateString(_ day: Int) -> String {
        return String(format: "%04d-%02d-%02d", currentYear, currentMonth, day)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 日历折叠栏
            VStack(spacing: 0) {
                HStack {
                    Button {
                        goToPreviousMonth()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundColor(Color(hex: "1E88E5"))
                            .padding(.trailing, 8)
                    }

                    Text(currentYearMonth)
                        .font(.subheadline)
                        .foregroundColor(.white)

                    Button {
                        goToNextMonth()
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundColor(canGoNext ? Color(hex: "1E88E5") : .gray.opacity(0.3))
                            .padding(.leading, 8)
                    }
                    .disabled(!canGoNext)

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCalendarExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isCalendarExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.gray)
                    }
                }
                .padding()

                if isCalendarExpanded {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                        Text("日").font(.caption).foregroundColor(.gray)
                        Text("一").font(.caption).foregroundColor(.gray)
                        Text("二").font(.caption).foregroundColor(.gray)
                        Text("三").font(.caption).foregroundColor(.gray)
                        Text("四").font(.caption).foregroundColor(.gray)
                        Text("五").font(.caption).foregroundColor(.gray)
                        Text("六").font(.caption).foregroundColor(.gray)

                        ForEach(Array(0..<firstWeekdayOffset).map { -$0 - 1 }, id: \.self) { _ in
                            Color.clear.frame(height: 40)
                        }

                        ForEach(daysOfMonth, id: \.self) { day in
                            let dateStr = makeDateString(day)
                            let hasData = datesWithData.contains(dateStr)
                            let count = monthData[dateStr] ?? 0

                            Button {
                                if hasData {
                                    selectedDate = dateStr
                                    loadUpdatesForDate(date: dateStr)
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Text("\(day)")
                                        .font(.system(size: 14, weight: selectedDate == dateStr ? .bold : .regular))
                                    if hasData && count > 0 {
                                        Text("\(count)")
                                            .font(.system(size: 9))
                                            .foregroundColor(Color(hex: "FFC107"))
                                    } else {
                                        Text("-")
                                            .font(.system(size: 9))
                                            .foregroundColor(.gray.opacity(0.3))
                                    }
                                }
                                .frame(height: 40)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(hasData
                                            ? (selectedDate == dateStr ? Color(hex: "FFC107") : Color(hex: "1E1E1E"))
                                            : Color(hex: "1E1E1E").opacity(0.3))
                                )
                                .foregroundColor(hasData ? (selectedDate == dateStr ? .black : .white) : .gray.opacity(0.3))
                            }
                            .disabled(!hasData)
                        }
                    }
                    .padding()
                }
            }
            .background(Color(hex: "1E1E1E"))

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
                        FinancialUpdateCard(stock: stock)
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
        .onAppear {
            loadMonthData(month: currentYearMonth)
        }
    }

    private func loadMonthData(month: String) {
        Task {
            do {
                guard let url = URL(string: "\(baseURL)/financial_updates/month/\(month)") else { return }
                let (data, response) = try await URLSession.shared.data(from: url)

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let result = try JSONDecoder().decode(MonthFinancialResponse.self, from: data)
                    if result.code == 0, let data = result.data {
                        var dates: [String] = []
                        var monthDataDict: [String: Int] = [:]
                        for item in data.dates {
                            dates.append(item.date)
                            monthDataDict[item.date] = item.count
                        }
                        await MainActor.run {
                            datesWithData = dates
                            monthData = monthDataDict
                            let today = String(format: "%04d-%02d-%02d", currentYear, currentMonth, calendar.component(.day, from: displayedDate))
                            if dates.contains(today) {
                                selectedDate = today
                            } else if let first = dates.first {
                                selectedDate = first
                            }
                        }
                    }
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
                guard let url = URL(string: "\(baseURL)/financial_updates/date/\(date)?sort_by=\(sortBy)&order=\(order)") else { return }
                let (data, response) = try await URLSession.shared.data(from: url)

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let result = try JSONDecoder().decode(FinancialUpdatesResponse.self, from: data)
                    if result.code == 0, let resultData = result.data {
                        await MainActor.run {
                            stockViewModel.financialUpdateStocks = resultData.stocks ?? []
                        }
                    }
                }
            } catch {
                print("加载失败: \(error)")
            }
        }
    }

    private func goToPreviousMonth() {
        if let newDate = calendar.date(byAdding: .month, value: -1, to: displayedDate) {
            displayedDate = newDate
            loadMonthData(month: currentYearMonth)
            selectedDate = ""
        }
    }

    private func goToNextMonth() {
        guard canGoNext else { return }
        if let newDate = calendar.date(byAdding: .month, value: 1, to: displayedDate) {
            displayedDate = newDate
            loadMonthData(month: currentYearMonth)
            selectedDate = ""
        }
    }

    private func reloadWithSort() {
        if selectedDate.isEmpty {
            let sortBy = currentSort == .yoy ? "net_profit_yoy" : "net_profit_qoq"
            let order = sortAscending ? "asc" : "desc"
            Task {
                do {
                    guard let url = URL(string: "\(baseURL)/financial_updates?sort_by=\(sortBy)&order=\(order)") else { return }
                    let (data, response) = try await URLSession.shared.data(from: url)
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                        let result = try JSONDecoder().decode(FinancialUpdatesResponse.self, from: data)
                        if result.code == 0, let resultData = result.data {
                            await MainActor.run {
                                stockViewModel.financialUpdateStocks = resultData.stocks ?? []
                            }
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