import SwiftUI

struct ChangeItem: Identifiable, Codable {
    var id: String { code }
    let code: String
    let name: String
    let type: String
    let sector: String?
    let price: Double?
    let change_pct: Double?

    enum CodingKeys: String, CodingKey {
        case code, name, type, sector, price, change_pct
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        sector = try container.decodeIfPresent(String.self, forKey: .sector)
        price = try Self.decodeNumeric(container: container, key: .price)
        change_pct = try Self.decodeNumeric(container: container, key: .change_pct)
    }

    private static func decodeNumeric(container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Double? {
        if let doubleValue = try? container.decode(Double.self, forKey: key) {
            return doubleValue
        }
        if let stringValue = try? container.decode(String.self, forKey: key), let doubleValue = Double(stringValue) {
            return doubleValue
        }
        return nil
    }
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

    enum CodingKeys: String, CodingKey {
        case code, name, sector, price, change_pct, removed_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        name = try container.decode(String.self, forKey: .name)
        sector = try container.decodeIfPresent(String.self, forKey: .sector)
        price = try Self.decodeNumeric(container: container, key: .price)
        change_pct = try Self.decodeNumeric(container: container, key: .change_pct)
        removed_at = try container.decodeIfPresent(String.self, forKey: .removed_at)
    }

    private static func decodeNumeric(container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Double? {
        if let doubleValue = try? container.decode(Double.self, forKey: key) {
            return doubleValue
        }
        if let stringValue = try? container.decode(String.self, forKey: key), let doubleValue = Double(stringValue) {
            return doubleValue
        }
        return nil
    }
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
    @State private var isCalendarExpanded = false
    @State private var displayedDate: Date = Date()

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

    private var dateData: [String: Int] {
        guard let removed = monthData?.removed else { return [:] }
        return removed.mapValues { $0.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            CalendarMonthPicker(
                displayedDate: $displayedDate,
                selectedDate: $selectedDate,
                isExpanded: $isCalendarExpanded,
                dateData: dateData,
                accentColor: Color(hex: "F44336"),
                canGoNext: canGoNext,
                onMonthChanged: { loadMonthData(month: $0) },
                onDateSelected: { date in Task { await loadChangesAsync(date: date) } }
            )

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
            loadMonthData(month: currentYearMonth)
        }
    }

    private func loadMonthData(month: String) {
        Task { @MainActor in
            isLoading = true
            errorMessage = nil

            do {
                let result: MonthResponse = try await APIClient.get("/changes/month/\(month)")
                if result.code == 0, let data = result.data {
                    monthData = data
                    if let lastDate = data.dates.last {
                        selectedDate = lastDate
                        await loadChangesAsync(date: lastDate)
                    }
                } else {
                    errorMessage = result.message ?? "未知错误"
                }
            } catch let error as APIClient.APIError {
                errorMessage = error.errorDescription
                print("[ChangesView] API错误(month): \(error)")
                if case .decodingError(let de) = error {
                    print("[ChangesView] 原始解码错误(MonthResponse): \(de)")
                }
            } catch let error as DecodingError {
                errorMessage = "数据解析失败"
                print("[ChangesView] 解码错误(MonthResponse): \(error)")
            } catch {
                errorMessage = error.localizedDescription
                print("[ChangesView] 其他错误(month): \(error)")
            }
            isLoading = false
        }
    }

    private func loadChangesAsync(date: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let result: ChangesResponse = try await APIClient.get("/changes/\(date)")
            if result.code == 0, let resultData = result.data {
                changesData = resultData
            } else {
                errorMessage = result.message ?? "未知错误"
            }
        } catch let error as APIClient.APIError {
            errorMessage = error.errorDescription
            print("[ChangesView] API错误: \(error)")
            if case .decodingError(let de) = error {
                print("[ChangesView] 原始解码错误(ChangesResponse): \(de)")
            }
        } catch let error as DecodingError {
            errorMessage = "数据解析失败"
            print("[ChangesView] 解码错误(ChangesResponse): \(error)")
        } catch {
            errorMessage = error.localizedDescription
            print("[ChangesView] 其他错误: \(error)")
        }
        isLoading = false
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
                .foregroundColor(Color(hex: "1E88E5"))
                .font(.title2)
        }
        .padding(.vertical, 8)
    }
}
