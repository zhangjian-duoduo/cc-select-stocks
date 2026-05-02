import SwiftUI

struct FilterView: View {
    @EnvironmentObject var stockViewModel: StockViewModel

    // 14个筛选条件
    @State private var momentumReversal = false  // 动量反转
    @State private var maAlignment = false       // 均线多头
    @State private var volumeBreak = false     // 放量突破
    @State private var lowVolume = false       // 明显缩量
    @State private var yoyPositive = false    // 业绩同比转正
    @State private var qoqPositive = false    // 业绩环比转正
    @State private var holderDecrease = false  // 股东减少
    @State private var volumeRiseStagnant = false  // 放量滞涨
    @State private var supportLevel = false   // 跌到支撑位
    @State private var resistanceLevel = false  // 涨到压力位
    @State private var highDividend = false    // 高股息
    @State private var lowPB = false          // 破净
    @State private var smallCap = false        // 小盘弹性
    @State private var sectorRotation = false  // 行业轮动

    @State private var isLoading = false
    @State private var filteredCount: Int? = nil

    private let baseURL = "http://8.163.91.16:5000/api/v1"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 标题
                Text("选择筛选条件")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                // 8个筛选条件
                VStack(spacing: 0) {
                    FilterToggleRow(
                        title: "动量反转",
                        subtitle: "跌幅>50% + MACD底背离 + 缩量",
                        isOn: $momentumReversal,
                        color: "4CAF50"
                    )

                    Divider().background(Color.gray.opacity(0.3))

                    FilterToggleRow(
                        title: "均线多头排列",
                        subtitle: "5日>10日>20日>60日均线",
                        isOn: $maAlignment,
                        color: "2196F3"
                    )

                    Divider().background(Color.gray.opacity(0.3))

                    FilterToggleRow(
                        title: "放量突破",
                        subtitle: "成交量放大 + 突破20日高点",
                        isOn: $volumeBreak,
                        color: "FF9800"
                    )

                    Divider().background(Color.gray.opacity(0.3))

                    FilterToggleRow(
                        title: "明显缩量",
                        subtitle: "成交量 < 20日均量50%",
                        isOn: $lowVolume,
                        color: "607D8B"
                    )

                    Divider().background(Color.gray.opacity(0.3))

                    FilterToggleRow(
                        title: "业绩同比转正",
                        subtitle: "净利润同比 > 0%",
                        isOn: $yoyPositive,
                        color: "4CAF50"
                    )

                    Divider().background(Color.gray.opacity(0.3))

                    FilterToggleRow(
                        title: "业绩环比转正",
                        subtitle: "净利润环比 > 0%",
                        isOn: $qoqPositive,
                        color: "8BC34A"
                    )

                    Divider().background(Color.gray.opacity(0.3))

                    FilterToggleRow(
                        title: "股东减少",
                        subtitle: "股东人数连续减少",
                        isOn: $holderDecrease,
                        color: "FF5722"
                    )

                    Divider().background(Color.gray.opacity(0.3))

                    FilterToggleRow(
                        title: "放量滞涨",
                        subtitle: "成交量放大但价格不涨",
                        isOn: $volumeRiseStagnant,
                        color: "FF5722"
                    )

                    Divider().background(Color.gray.opacity(0.3))

                    FilterToggleRow(
                        title: "跌到支撑位",
                        subtitle: "价格接近20日低点",
                        isOn: $supportLevel,
                        color: "2196F3"
                    )

                    Divider().background(Color.gray.opacity(0.3))

                    FilterToggleRow(
                        title: "涨到压力位",
                        subtitle: "价格接近20日高点",
                        isOn: $resistanceLevel,
                        color: "F44336"
                    )

                    Divider().background(Color.gray.opacity(0.3))

                    FilterToggleRow(
                        title: "高股息",
                        subtitle: "股息率 > 3%",
                        isOn: $highDividend,
                        color: "9C27B0"
                    )

                    Divider().background(Color.gray.opacity(0.3))

                    FilterToggleRow(
                        title: "破净价值",
                        subtitle: "市净率 < 1",
                        isOn: $lowPB,
                        color: "E91E63"
                    )

                    Divider().background(Color.gray.opacity(0.3))

                    FilterToggleRow(
                        title: "小盘弹性",
                        subtitle: "市值 < 30亿",
                        isOn: $smallCap,
                        color: "00BCD4"
                    )

                    Divider().background(Color.gray.opacity(0.3))

                    FilterToggleRow(
                        title: "行业轮动",
                        subtitle: "热门行业优先",
                        isOn: $sectorRotation,
                        color: "795548"
                    )
                }
                .background(Color(hex: "1E1E1E"))
                .cornerRadius(12)
                .padding(.horizontal)

                // 筛选按钮
                HStack(spacing: 12) {
                    Button(action: {
                        clearAllFilters()
                    }) {
                        Text("清除条件")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(hex: "607D8B"))
                            .cornerRadius(12)
                    }

                    Button(action: {
                        applyFilter()
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
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
    }

    private func applyFilter() {
        var filters: [String] = []

        if momentumReversal { filters.append("momentum_reversal") }
        if maAlignment { filters.append("ma_alignment") }
        if volumeBreak { filters.append("volume_break") }
        if lowVolume { filters.append("low_volume") }
        if yoyPositive { filters.append("yoy_positive") }
        if qoqPositive { filters.append("qoq_positive") }
        if holderDecrease { filters.append("holder_decrease") }
        if volumeRiseStagnant { filters.append("volume_rise_stagnant") }
        if supportLevel { filters.append("support_level") }
        if resistanceLevel { filters.append("resistance_level") }
        if highDividend { filters.append("high_dividend") }
        if lowPB { filters.append("low_pb") }
        if smallCap { filters.append("small_cap") }
        if sectorRotation { filters.append("sector_rotation") }

        isLoading = true

        Task { @MainActor in
            do {
                guard let url = URL(string: "\(baseURL)/filter") else {
                    isLoading = false
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 180

                let body = ["filters": filters]
                request.httpBody = try JSONEncoder().encode(body)

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    print("[筛选] 无效响应")
                    isLoading = false
                    return
                }

                print("[筛选] HTTP状态: \(httpResponse.statusCode), 数据长度: \(data.count)")

                guard httpResponse.statusCode == 200 else {
                    print("[筛选] 服务器错误: \(httpResponse.statusCode)")
                    isLoading = false
                    return
                }

                // 打印响应预览
                if let jsonStr = String(data: data, encoding: .utf8) {
                    print("[筛选] 响应预览: \(String(jsonStr.prefix(200)))")
                }

                let result = try JSONDecoder().decode(StockResponse.self, from: data)
                print("[筛选] code=\(result.code), data=\(result.data?.count ?? -1), total=\(result.total ?? -1)")

                if result.code == 0, let filtered = result.data {
                    filteredCount = filtered.count
                    print("[筛选] 成功! 筛选前: \(stockViewModel.stocks.count), 筛选后: \(filtered.count)")
                    stockViewModel.stocks = filtered
                    stockViewModel.applySort()
                    // 直接用 stockViewModel 保存筛选条件，不触发 didSet 的重复API调用
                    stockViewModel.saveFiltersDirectly(Set(filters))
                } else {
                    print("[筛选] API错误: code=\(result.code), message=\(result.message ?? "无")")
                }
            } catch {
                print("[筛选] 失败: \(error)")
            }
            isLoading = false
        }
    }

    private func clearAllFilters() {
        momentumReversal = false
        maAlignment = false
        volumeBreak = false
        lowVolume = false
        yoyPositive = false
        qoqPositive = false
        holderDecrease = false
        volumeRiseStagnant = false
        supportLevel = false
        resistanceLevel = false
        highDividend = false
        lowPB = false
        smallCap = false
        sectorRotation = false
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
