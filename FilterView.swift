import SwiftUI

struct FilterView: View {
    @EnvironmentObject var stockViewModel: StockViewModel

    // 8个筛选条件
    @State private var momentumReversal = false  // 动量反转
    @State private var maAlignment = false       // 均线多头
    @State private var volumeBreak = false     // 放量突破
    @State private var highDividend = false    // 高股息
    @State private var lowPB = false          // 破净
    @State private var smallCap = false        // 小盘弹性
    @State private var holderDecrease = false  // 股东减少
    @State private var sectorRotation = false  // 行业轮动

    @State private var isLoading = false
    @State private var filteredCount: Int = 0

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
                        title: "股东减少",
                        subtitle: "股东人数连续减少",
                        isOn: $holderDecrease,
                        color: "FF5722"
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
                .padding(.horizontal)

                // 结果显示
                if filteredCount > 0 {
                    Text("筛选结果: \(filteredCount) 只股票")
                        .font(.subheadline)
                        .foregroundColor(Color(hex: "4CAF50"))
                        .padding(.top, 8)
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
        if highDividend { filters.append("high_dividend") }
        if lowPB { filters.append("low_pb") }
        if smallCap { filters.append("small_cap") }
        if holderDecrease { filters.append("holder_decrease") }
        if sectorRotation { filters.append("sector_rotation") }

        isLoading = true

        Task {
            do {
                guard let url = URL(string: "\(baseURL)/filter") else {
                    isLoading = false
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 60

                let body = ["filters": filters]
                request.httpBody = try JSONEncoder().encode(body)

                let (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let result = try JSONDecoder().decode(StockResponse.self, from: data)
                    if result.code == 0 {
                        filteredCount = result.data?.count ?? 0
                        stockViewModel.stocks = result.data ?? []
                        stockViewModel.applySort()
                    }
                }
            } catch {
                print("筛选失败: \(error)")
            }
            isLoading = false
        }
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
