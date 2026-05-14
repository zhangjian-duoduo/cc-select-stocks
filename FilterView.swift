import SwiftUI

// MARK: - 筛选条件定义（单一数据源，增删条件只需改这里）

struct FilterCondition: Identifiable {
    let id: String         // API filter name
    let title: String
    let subtitle: String
    let color: String

    static let all: [FilterCondition] = [
        .init(id: "momentum_reversal",      title: "动量反转",     subtitle: "跌幅>50% + MACD底背离 + 缩量",    color: "4CAF50"),
        .init(id: "ma_alignment",           title: "均线多头排列", subtitle: "5日>10日>20日>60日均线",           color: "2196F3"),
        .init(id: "volume_break",           title: "放量突破",     subtitle: "成交量放大 + 突破20日高点",          color: "FF9800"),
        .init(id: "low_volume",             title: "明显缩量",     subtitle: "成交量 < 20日均量50%",              color: "607D8B"),
        .init(id: "yoy_positive",           title: "业绩同比转正", subtitle: "净利润同比 > 0%",                    color: "4CAF50"),
        .init(id: "qoq_positive",           title: "业绩环比转正", subtitle: "净利润环比 > 0%",                    color: "8BC34A"),
        .init(id: "holder_decrease",        title: "股东减少",     subtitle: "股东人数连续减少",                   color: "FF5722"),
        .init(id: "volume_rise_stagnant",   title: "放量滞涨",     subtitle: "成交量放大但价格不涨",               color: "FF5722"),
        .init(id: "support_level",          title: "跌到支撑位",   subtitle: "价格接近20日低点",                   color: "2196F3"),
        .init(id: "resistance_level",       title: "涨到压力位",   subtitle: "价格接近20日高点",                   color: "F44336"),
        .init(id: "high_dividend",          title: "高股息",       subtitle: "股息率 > 3%",                       color: "9C27B0"),
        .init(id: "low_pb",                 title: "破净价值",     subtitle: "市净率 < 1",                         color: "E91E63"),
        .init(id: "small_cap",              title: "小盘弹性",     subtitle: "市值 < 30亿",                        color: "00BCD4"),
        .init(id: "sector_rotation",        title: "行业轮动",     subtitle: "热门行业优先",                        color: "795548"),
    ]
}

struct FilterView: View {
    @EnvironmentObject var stockViewModel: StockViewModel

    @State private var activeFilters: Set<String> = []
    @State private var isLoading = false
    @State private var filteredCount: Int? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 自定义筛选入口
                NavigationLink(destination: DynamicScreeningView()) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自定义筛选")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("每个条件可独立开关，灵活组合")
                                .font(.caption)
                                .foregroundColor(Color(hex: "90CAF9"))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }
                .padding(.horizontal)

                Text("预设筛选条件")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                VStack(spacing: 0) {
                    ForEach(Array(FilterCondition.all.enumerated()), id: \.element.id) { index, condition in
                        FilterToggleRow(
                            title: condition.title,
                            subtitle: condition.subtitle,
                            isOn: binding(for: condition.id),
                            color: condition.color
                        )
                        if index < FilterCondition.all.count - 1 {
                            Divider().background(Color.gray.opacity(0.3))
                        }
                    }
                }
                .background(Color(hex: "1E1E1E"))
                .cornerRadius(12)
                .padding(.horizontal)

                // 筛选按钮
                HStack(spacing: 12) {
                    Button(action: clearAllFilters) {
                        Text("清除条件")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(hex: "607D8B"))
                            .cornerRadius(12)
                    }

                    Button(action: applyFilter) {
                        HStack {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("应用筛选")
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "1E88E5"))
                        .cornerRadius(12)
                    }
                    .disabled(isLoading)
                }
                .padding(.horizontal)

                // 结果显示
                if let count = filteredCount {
                    if count > 0 {
                        Text("筛选结果: \(count) 只股票")
                            .font(.subheadline)
                            .foregroundColor(Color(hex: "4CAF50"))
                            .padding(.top, 8)
                    } else {
                        Text("无匹配结果，请调整筛选条件")
                            .font(.subheadline)
                            .foregroundColor(Color(hex: "FF9800"))
                            .padding(.top, 8)
                    }
                }

                Spacer()
            }
            .padding(.vertical)
        }
        .background(Color(hex: "121212"))
        .navigationTitle("筛选")
        .onAppear {
            // 恢复已保存的筛选条件
            if activeFilters.isEmpty && !stockViewModel.activeFilters.isEmpty {
                activeFilters = stockViewModel.activeFilters
            }
        }
    }

    // MARK: - Helpers

    private func binding(for filterId: String) -> Binding<Bool> {
        Binding(
            get: { activeFilters.contains(filterId) },
            set: { newValue in
                if newValue { activeFilters.insert(filterId) }
                else { activeFilters.remove(filterId) }
            }
        )
    }

    private func applyFilter() {
        guard !activeFilters.isEmpty else {
            clearAllFilters()
            return
        }

        isLoading = true
        let filters = Array(activeFilters)

        Task { @MainActor in
            do {
                let result: StockResponse = try await APIClient.post("/filter", body: ["filters": filters])
                if result.code == 0, let filtered = result.data {
                    filteredCount = filtered.count
                    stockViewModel.stocks = filtered
                    stockViewModel.applySort()
                    stockViewModel.saveFiltersDirectly(activeFilters)
                }
            } catch {
                print("[筛选] 失败: \(error)")
            }
            isLoading = false
        }
    }

    private func clearAllFilters() {
        activeFilters.removeAll()
        filteredCount = nil
        stockViewModel.stocks = stockViewModel.allStocks
        stockViewModel.applySort()
        stockViewModel.clearFilters()
    }
}

struct FilterToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let color: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .tint(Color(hex: color))
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationStack {
        FilterView()
    }
    .environmentObject(StockViewModel())
    .preferredColorScheme(.dark)
}
