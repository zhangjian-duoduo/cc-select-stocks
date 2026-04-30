import SwiftUI

struct ChangeItem: Identifiable, Codable {
    var id: String { code }
    let code: String
    let name: String
    let type: String
    let sector: String?
    let price: Double?
    let change_pct: Double?
}

struct ChangesData: Codable {
    let date: String
    let new: [ChangeItem]
    let removed: [ChangeItem]
    let new_count: Int
    let removed_count: Int
}

struct ChangesResponse: Codable {
    let code: Int
    let data: ChangesData?
    let message: String?
}

struct RemovedItem: Identifiable, Codable {
    var id: String { code }
    let code: String
    let name: String
    let sector: String?
    let price: Double?
    let change_pct: Double?
    let removed_at: String?
}

struct MonthData: Codable {
    let month: String
    let dates: [String]
    let removed: [String: [RemovedItem]]
}

struct MonthResponse: Codable {
    let code: Int
    let data: MonthData?
    let message: String?
}

struct ChangesView: View {
    @State private var changesData: ChangesData?
    @State private var monthData: MonthData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedTab = 0
    @State private var selectedDate: String = ""
    @State private var selectedMonth: String = ""
    @State private var isCalendarExpanded = false

    private let baseURL = "http://8.163.91.16:5000/api/v1"

    private var currentYearMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    private var currentYear: Int {
        let parts = currentYearMonth.split(separator: "-")
        return parts.count >= 1 ? Int(parts[0]) ?? 2026 : 2026
    }

    private var currentMonth: Int {
        let parts = currentYearMonth.split(separator: "-")
        return parts.count >= 2 ? Int(parts[1]) ?? 4 : 4
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

    private func makeDateString(_ day: Int) -> String {
        return String(format: "%04d-%02d-%02d", currentYear, currentMonth, day)
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

    private func loadMonthData(month: String) {
        Task { @MainActor in
            isLoading = true
            errorMessage = nil

            do {
                guard let url = URL(string: "\(baseURL)/changes/month/\(month)") else {
                    errorMessage = "URL错误"
                    isLoading = false
                    return
                }

                let (data, response) = try await URLSession.shared.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    errorMessage = "服务器错误"
                    isLoading = false
                    return
                }

                let result = try JSONDecoder().decode(MonthResponse.self, from: data)
                if result.code == 0, let data = result.data {
                    monthData = data
                    if let lastDate = data.dates.last {
                        selectedDate = lastDate
                        loadChanges(date: lastDate)
                    }
                } else {
                    errorMessage = result.message ?? "未知错误"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func loadChanges(date: String) {
        Task { @MainActor in
            isLoading = true

            do {
                guard let url = URL(string: "\(baseURL)/changes/\(date)") else {
                    isLoading = false
                    return
                }

                let (data, response) = try await URLSession.shared.data(from: url)

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let result = try JSONDecoder().decode(ChangesResponse.self, from: data)
                    if result.code == 0, let resultData = result.data {
                        changesData = resultData
                    } else {
                        print("API error: \(result.message ?? "unknown")")
                    }
                }
            } catch {
                print("加载变化失败: \(error)")
            }
            isLoading = false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 月份选择器和日历开关
            VStack(spacing: 0) {
                HStack {
                    Button {
                        selectedMonth = currentYearMonth
                        loadMonthData(month: currentYearMonth)
                    } label: {
                        Text(currentYearMonth)
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedMonth == currentYearMonth ? Color(hex: "1E88E5") : Color(hex: "1E1E1E"))
                            .foregroundColor(selectedMonth == currentYearMonth ? .white : .gray)
                            .cornerRadius(8)
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCalendarExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isCalendarExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.gray)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
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

                        ForEach(0..<firstWeekdayOffset, id: \.self) { _ in
                            Text("").frame(height: 40)
                        }

                        ForEach(daysOfMonth, id: \.self) { day in
                            let dateStr = makeDateString(day)
                            let hasData = monthData?.dates.contains(dateStr) ?? false
                            let removedCount = monthData?.removed[dateStr]?.count ?? 0

                            Button {
                                if hasData {
                                    selectedDate = dateStr
                                    loadChanges(date: dateStr)
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Text("\(day)")
                                        .font(.system(size: 16, weight: selectedDate == dateStr ? .bold : .regular))
                                    if hasData && removedCount > 0 {
                                        Text("\(removedCount)")
                                            .font(.system(size: 10))
                                            .foregroundColor(Color(hex: "F44336"))
                                    } else {
                                        Text("-")
                                            .font(.system(size: 10))
                                            .foregroundColor(.gray.opacity(0.3))
                                    }
                                }
                                .frame(height: 50)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(hasData
                                            ? (selectedDate == dateStr ? Color(hex: "F44336") : Color(hex: "1E1E1E"))
                                            : Color(hex: "1E1E1E").opacity(0.3))
                                )
                                .foregroundColor(hasData ? (selectedDate == dateStr ? .white : .gray) : .gray.opacity(0.3))
                            }
                            .disabled(!hasData)
                        }
                    }
                    .padding()
                }
            }
            .background(Color(hex: "1E1E1E"))

            if let data = changesData {
                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("\(data.new_count)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(Color(hex: "4CAF50"))
                        Text("新入选")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)

                    VStack(spacing: 4) {
                        Text("\(data.removed_count)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(Color(hex: "F44336"))
                        Text("已剔除")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }
                .padding()
            }

            Picker("类型", selection: $selectedTab) {
                Text("新入选 (\(changesData?.new_count ?? 0))").tag(0)
                Text("已剔除 (\(changesData?.removed_count ?? 0))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                Text("错误: \(error)")
                    .foregroundColor(.red)
                Spacer()
            } else if let data = changesData {
                List {
                    if selectedTab == 0 {
                        ForEach(data.new) { item in
                            ChangeRow(item: item, isNew: true)
                                .listRowBackground(Color(hex: "1E1E1E"))
                        }
                    } else {
                        ForEach(data.removed) { item in
                            ChangeRow(item: item, isNew: false)
                                .listRowBackground(Color(hex: "1E1E1E"))
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                Spacer()
                Text("选择月份和日期查看")
                    .foregroundColor(.gray)
                Spacer()
            }
        }
        .background(Color(hex: "121212"))
        .navigationTitle("每日变化")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM"
            selectedMonth = formatter.string(from: Date())
            loadMonthData(month: selectedMonth)
        }
    }
}

struct ChangeRow: View {
    let item: ChangeItem
    let isNew: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name)
                        .font(.headline)
                        .foregroundColor(.white)
                    if let sector = item.sector, !sector.isEmpty {
                        Text(sector)
                            .font(.caption)
                            .foregroundColor(Color(hex: "1E88E5"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "1E88E5").opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                Text(item.code)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let price = item.price {
                    Text(String(format: "%.2f", price))
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                if let change = item.change_pct {
                    Text(String(format: "%+.2f%%", change))
                        .font(.caption)
                        .foregroundColor(change >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                }
            }

            Image(systemName: isNew ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(isNew ? Color(hex: "4CAF50") : Color(hex: "F44336"))
                .font(.title2)
        }
        .padding(.vertical, 8)
    }
}