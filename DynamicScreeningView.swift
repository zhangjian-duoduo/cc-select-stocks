import SwiftUI

// MARK: - 动态自定义筛选页面

struct DynamicScreeningView: View {
    @EnvironmentObject var stockViewModel: StockViewModel

    @State private var conditions: [String: Bool] = {
        var dict: [String: Bool] = [:]
        for c in ScreeningCondition.all {
            dict[c.id] = true
        }
        // CAGR 和机构持股默认 OFF
        dict["rev_cagr_over_30"] = false
        dict["inst_ownership_over_5"] = false
        return dict
    }()

    @State private var isLoading = false
    @State private var showResults = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 分组筛选条件
                ForEach(ScreeningSection.allCases, id: \.self) { section in
                    sectionCard(section)
                }

                // 操作按钮
                HStack(spacing: 12) {
                    Button(action: resetAll) {
                        Text("重置")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(hex: "607D8B"))
                            .cornerRadius(12)
                    }

                    Button(action: applyScreening) {
                        HStack {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("开始筛选")
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(enabledCount > 0 ? Color(hex: "1E88E5") : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(isLoading || enabledCount == 0)
                }
                .padding(.horizontal)

                // 筛选结果
                if showResults {
                    resultSection
                }

                Spacer()
            }
            .padding(.vertical)
        }
        .background(Color(hex: "121212"))
        .navigationTitle("自定义筛选")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Section

    @ViewBuilder
    private func sectionCard(_ section: ScreeningSection) -> some View {
        let sectionConditions = ScreeningCondition.all.filter { $0.section == section }

        VStack(spacing: 0) {
            Text(section.rawValue)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(Color(hex: "90CAF9"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ForEach(Array(sectionConditions.enumerated()), id: \.element.id) { index, condition in
                ScreeningToggleRow(
                    title: condition.title,
                    subtitle: condition.subtitle,
                    isOn: binding(for: condition.id)
                )
                if index < sectionConditions.count - 1 {
                    Divider().background(Color.gray.opacity(0.2))
                }
            }
        }
        .background(Color(hex: "1E1E1E"))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultSection: some View {
        VStack(spacing: 12) {
            if stockViewModel.screeningResults.isEmpty {
                Text("无匹配结果，请调整筛选条件")
                    .font(.subheadline)
                    .foregroundColor(Color(hex: "FF9800"))
                    .padding(.top, 8)
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Text("筛选结果: \(stockViewModel.screeningTotal) 只股票")
                            .font(.headline)
                            .foregroundColor(Color(hex: "4CAF50"))
                        Spacer()
                        if let stats = stockViewModel.screeningStats {
                            Text("扫描 \(stats.total_scanned ?? 0) 只")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }

                    Text("已启用 \(enabledCount)/\(ScreeningCondition.all.count) 个条件")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // 显示匹配的股票列表
                    VStack(spacing: 0) {
                        ForEach(stockViewModel.screeningResults) { stock in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stock.name)
                                        .font(.body)
                                        .foregroundColor(.white)
                                    Text(stock.code)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                if let concepts = stock.concepts, !concepts.isEmpty {
                                    Text(concepts.prefix(2).joined(separator: " · "))
                                        .font(.caption2)
                                        .foregroundColor(Color(hex: "90CAF9"))
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            if stock.id != stockViewModel.screeningResults.last?.id {
                                Divider().background(Color.gray.opacity(0.15))
                            }
                        }
                    }
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Actions

    private var enabledCount: Int {
        conditions.values.filter { $0 }.count
    }

    private func binding(for conditionId: String) -> Binding<Bool> {
        Binding(
            get: { conditions[conditionId] ?? false },
            set: { conditions[conditionId] = $0 }
        )
    }

    private func applyScreening() {
        guard enabledCount > 0 else { return }
        isLoading = true
        showResults = false

        Task { @MainActor in
            await stockViewModel.applyCustomScreening(conditions)
            isLoading = false
            showResults = true
        }
    }

    private func resetAll() {
        for c in ScreeningCondition.all {
            conditions[c.id] = true
        }
        conditions["rev_cagr_over_30"] = false
        conditions["inst_ownership_over_5"] = false
        showResults = false
        stockViewModel.clearCustomScreening()
    }
}

// MARK: - Toggle Row for Screening

struct ScreeningToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

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
                .tint(Color(hex: "4CAF50"))
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationStack {
        DynamicScreeningView()
    }
    .environmentObject(StockViewModel())
    .preferredColorScheme(.dark)
}
