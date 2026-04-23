import SwiftUI
import Charts

struct StockListView: View {
    @EnvironmentObject var stockViewModel: StockViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = stockViewModel.errorMessage {
                Text("错误: \(error)")
                    .foregroundColor(.red)
                    .padding()
            }

            if stockViewModel.stocks.isEmpty && !stockViewModel.isLoading {
                Text("暂无数据")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 排序选项栏
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            SortButton(
                                title: option.rawValue,
                                isSelected: stockViewModel.sortOption == option,
                                isAscending: stockViewModel.sortOption == option ? stockViewModel.sortAscending : nil
                            ) {
                                stockViewModel.toggleSort(option)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(hex: "1E1E1E"))

                // 股票列表
                List {
                    ForEach(stockViewModel.filteredStocks) { stock in
                        NavigationLink(destination: StockDetailView(stock: stock)) {
                            StockCard(stock: stock, sortOption: stockViewModel.sortOption)
                        }
                        .listRowBackground(Color(hex: "1E1E1E"))
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(hex: "121212"))
        .navigationTitle("智能选股")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await stockViewModel.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .refreshable {
            await stockViewModel.refresh()
        }
    }
}

struct SortButton: View {
    let title: String
    let isSelected: Bool
    let isAscending: Bool?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)

                if isSelected, let ascending = isAscending {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color(hex: "1E88E5") : Color(hex: "2C2C2C"))
            .foregroundColor(isSelected ? .white : .gray)
            .cornerRadius(20)
        }
    }
}

struct StockCard: View {
    let stock: Stock
    var sortOption: SortOption = .position
    @EnvironmentObject var stockViewModel: StockViewModel

    init(stock: Stock, sortOption: SortOption = .position) {
        self.stock = stock
        self.sortOption = sortOption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stock.name)
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(stock.code)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                // 收藏按钮
                Button {
                    stockViewModel.toggleFavorite(stock)
                } label: {
                    Image(systemName: stockViewModel.isFavorited(stock.code) ? "star.fill" : "star")
                        .foregroundColor(stockViewModel.isFavorited(stock.code) ? Color(hex: "FFC107") : .gray)
                        .font(.title3)
                }
            }

            HStack {
                Text(String(format: "¥%.2f", stock.price ?? 0))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Spacer()

                let changePct = stock.change_pct ?? 0
                HStack(spacing: 4) {
                    Image(systemName: changePct >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(String(format: "%.2f%%", changePct))
                }
                .foregroundColor(changePct >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
            }

            // 排序指标显示
            sortIndicatorView
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var sortIndicatorView: some View {
        HStack(spacing: 4) {
            // 涨跌指标 - 显示5年涨跌幅
            SortMetricView(
                title: "涨跌",
                value: String(format: "%.1f%%", stock.change_5y ?? 0),
                isHighlighted: sortOption == .dailyChange,
                color: (stock.change_5y ?? 0) >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50")
            )

            // 位置指标
            SortMetricView(
                title: "位置",
                value: stock.price_position.map { "\(Int($0 * 100))" } ?? "-",
                isHighlighted: sortOption == .position,
                color: colorForPosition(stock.price_position)
            )

            // 评分指标
            SortMetricView(
                title: "评分",
                value: calculateScore(),
                isHighlighted: sortOption == .score,
                color: colorForScore(calculateScore())
            )

            // 筹码指标
            SortMetricView(
                title: "筹码",
                value: stock.chip_concentration.map { String(format: "%.0f", $0 * 100) } ?? "-",
                isHighlighted: sortOption == .chip,
                color: colorForChip(stock.chip_concentration)
            )

            // 股东指标
            SortMetricView(
                title: "股东",
                value: shareholderTrendValue(),
                isHighlighted: sortOption == .shareholder,
                color: colorForShareholder(shareholderTrendValue())
            )

            // 底背离指标 - 显示具体级别
            SortMetricView(
                title: "背离",
                value: divergenceDisplayText(),
                isHighlighted: sortOption == .bottomDivergence,
                color: colorForDivergence()
            )
        }
        .padding(.horizontal, 4)
    }

    private func calculateScore() -> String {
        // 与StockViewModel保持一致的评分算法
        // 1. 趋势得分 (30%)
        let trendScore = trendScoreValue()

        // 2. 估值得分 (25%)
        let pricePct = stock.price_percentile ?? 50
        let valuationScore = (100 - pricePct) / 100.0

        // 3. 筹码得分 (20%)
        let chipScore = (stock.chip_concentration ?? 50) / 100.0

        // 4. 股东变化得分 (15%)
        let holderPct = shareholderChangePercent()
        let holderScore: Double
        if holderPct < -10 {
            holderScore = 1.0
        } else if holderPct < 0 {
            holderScore = 0.7
        } else if holderPct < 20 {
            holderScore = 0.4
        } else {
            holderScore = 0.1
        }

        // 5. 背离得分 (10%)
        var divergenceScore: Double = 0
        if stock.macd_divergence?.monthly == true { divergenceScore += 0.5 }
        if stock.macd_divergence?.weekly == true { divergenceScore += 0.3 }
        if stock.macd_divergence?.daily == true { divergenceScore += 0.2 }

        let total = trendScore * 0.30 + valuationScore * 0.25 + chipScore * 0.20 + holderScore * 0.15 + divergenceScore * 0.10
        return String(format: "%.0f", min(1.0, max(0.0, total)) * 100)
    }

    private func trendScoreValue() -> Double {
        guard let t = stock.trend_analysis else { return 0.5 }
        switch t.short {
        case "上涨趋势": return 1.0
        case "震荡": return 0.6
        case "下跌趋势": return 0.2
        default: return 0.5
        }
    }

    private func shareholderChangePercent() -> Double {
        guard let trend = stock.holders_trend, trend.count >= 2 else { return 0 }
        let oldest = trend.last?.holders ?? 0
        let newest = trend.first?.holders ?? 0
        if oldest > 0 {
            return Double(newest - oldest) / Double(oldest) * 100
        }
        return 0
    }

    private func shareholderTrendValue() -> String {
        // 显示5年来股东人数变化百分比
        guard let trend = stock.holders_trend, trend.count >= 2 else { return "-" }
        let oldest = trend.last?.holders ?? 0
        let newest = trend.first?.holders ?? 0
        guard oldest > 0 else { return "-" }
        let pct = Double(newest - oldest) / Double(oldest) * 100
        if pct > 0 {
            return "+\(String(format: "%.1f", pct))%"
        } else {
            return "\(String(format: "%.1f", pct))%"
        }
    }

    // 获取背离级别显示文本
    private func divergenceDisplayText() -> String {
        guard let div = stock.macd_divergence else { return "-" }
        var levels: [String] = []
        if div.daily == true { levels.append("日") }
        if div.weekly == true { levels.append("周") }
        if div.monthly == true { levels.append("月") }
        return levels.isEmpty ? "-" : levels.joined(separator: "/") + "背"
    }

    // 背离颜色
    private func colorForDivergence() -> Color {
        guard let div = stock.macd_divergence else { return .gray }
        if div.monthly == true { return Color(hex: "4CAF50") }  // 月背离最强
        else if div.weekly == true { return Color(hex: "1E88E5") }
        else if div.daily == true { return Color(hex: "FFC107") }
        else { return .gray }
    }

    private func colorForPosition(_ position: Double?) -> Color {
        guard let pos = position else { return .gray }
        if pos < 0.15 { return Color(hex: "4CAF50") }
        else if pos < 0.3 { return Color(hex: "1E88E5") }
        else { return Color(hex: "FFC107") }
    }

    private func colorForScore(_ score: String) -> Color {
        guard let value = Double(score), value > 0 else { return .gray }
        if value >= 70 { return Color(hex: "4CAF50") }
        else if value >= 50 { return Color(hex: "1E88E5") }
        else { return Color(hex: "FFC107") }
    }

    private func colorForChip(_ chip: Double?) -> Color {
        guard let c = chip else { return .gray }
        if c >= 80 { return Color(hex: "4CAF50") }
        else if c >= 60 { return Color(hex: "1E88E5") }
        else { return Color(hex: "FFC107") }
    }

    private func colorForShareholder(_ value: String) -> Color {
        if value == "-" { return .gray }
        if value.hasPrefix("+") { return Color(hex: "F44336") } // 股东增加 = 分散
        if let num = Double(value.replacingOccurrences(of: "%", with: "")), num < -10 { return Color(hex: "4CAF50") } // 大幅减少 = 集中
        return Color(hex: "FFC107")
    }
}

struct SortMetricView: View {
    let title: String
    let value: String
    let isHighlighted: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 11))
                .fontWeight(isHighlighted ? .bold : .regular)
                .foregroundColor(isHighlighted ? color : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.system(size: 10))
                .foregroundColor(isHighlighted ? color : .gray)
        }
        .frame(width: 38)
        .padding(.vertical, 4)
        .background(isHighlighted ? color.opacity(0.2) : Color.clear)
        .cornerRadius(6)
    }
}

struct StockDetailView: View {
    let stock: Stock

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 基本信息
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(stock.name)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text(stock.code)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }

                    HStack {
                        Text("当前价格")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                        Text(String(format: "¥%.2f", stock.price ?? 0))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                .padding()
                .background(Color(hex: "1E1E1E"))
                .cornerRadius(12)

                // 股东人数趋势
                if let holders = stock.holders_trend, !holders.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("股东人数趋势")
                            .font(.headline)
                            .foregroundColor(.white)

                        // 股东趋势图 - 带渐变色
                        Chart {
                            ForEach(holders.indices, id: \.self) { index in
                                LineMark(
                                    x: .value("季度", index),
                                    y: .value("股东", holders[index].holders ?? 0)
                                )
                                .foregroundStyle(Color(hex: "1E88E5"))

                                AreaMark(
                                    x: .value("季度", index),
                                    y: .value("股东", holders[index].holders ?? 0)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "1E88E5").opacity(0.3), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                PointMark(
                                    x: .value("季度", index),
                                    y: .value("股东", holders[index].holders ?? 0)
                                )
                                .foregroundStyle(Color(hex: "1E88E5"))
                                .symbolSize(30)
                            }
                        }
                        .frame(height: 160)
                        .chartXAxis {
                            AxisMarks(values: .automatic) { _ in
                                AxisValueLabel()
                                    .foregroundStyle(Color.gray)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in
                                AxisValueLabel()
                                    .foregroundStyle(Color.gray)
                            }
                        }

                        // 统计信息
                        HStack {
                            VStack(alignment: .leading) {
                                Text("最新股东")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text("\(holders.last?.holders ?? 0)")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                            Spacer()
                            let latest = holders.last?.holders ?? 0
                            let earliest = holders.first?.holders ?? 0
                            let change = earliest > 0 ? Double(latest - earliest) / Double(earliest) * 100 : 0
                            VStack(alignment: .trailing) {
                                Text("5年变化")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(String(format: "%.1f%%", change))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundColor(change >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                            }
                        }
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }

                // 5年涨跌
                if let change5y = stock.change_5y {
                    HStack {
                        Text("5年涨跌")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Text(String(format: "%.2f%%", change5y))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(change5y >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }

                // 价格分位 - 使用Gauge仪表盘
                if let pricePct = stock.price_percentile {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("当前价格历史分位")
                            .font(.headline)
                            .foregroundColor(.white)

                        HStack {
                            Gauge(value: pricePct, in: 0...100) {
                                Text("价格分位")
                            } currentValueLabel: {
                                Text("\(Int(pricePct))%")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            .gaugeStyle(.accessoryCircular)
                            .tint(valuationColor(pricePct))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("价格分位")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text(pricePositionDescription(pricePct))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.leading)
                        }
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }

                // MACD底背离
                if let macd = stock.macd_divergence {
                    let hasDivergence = (macd.daily == true || macd.weekly == true || macd.monthly == true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("MACD底背离信号")
                            .font(.headline)
                            .foregroundColor(.white)

                        HStack {
                            Image(systemName: hasDivergence ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(hasDivergence ? Color(hex: "4CAF50") : Color(hex: "F44336"))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(hasDivergence ? "已出现底背离信号" : "未出现底背离信号")
                                    .font(.subheadline)
                                    .foregroundColor(.white)

                                Text(hasDivergence ? "股价创新低但MACD未创新低，反弹概率较大" : "无明显底背离信号")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }

                            Spacer()
                        }

                        // 详细周期
                        HStack(spacing: 20) {
                            VStack {
                                Text("日线")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Image(systemName: (macd.daily ?? false) ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundColor((macd.daily ?? false) ? Color(hex: "4CAF50") : .gray)
                            }
                            VStack {
                                Text("周线")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Image(systemName: (macd.weekly ?? false) ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundColor((macd.weekly ?? false) ? Color(hex: "4CAF50") : .gray)
                            }
                            VStack {
                                Text("月线")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Image(systemName: (macd.monthly ?? false) ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundColor((macd.monthly ?? false) ? Color(hex: "4CAF50") : .gray)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }

                // 趋势分析
                if let trend = stock.trend_analysis {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("趋势分析")
                            .font(.headline)
                            .foregroundColor(.white)

                        HStack {
                            VStack {
                                Text("短期")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(trend.short ?? "-")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            }
                            Spacer()
                            VStack {
                                Text("中期")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(trend.medium ?? "-")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            }
                            Spacer()
                            VStack {
                                Text("长期")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(trend.long ?? "-")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }

                // 筹码集中度
                if let chip = stock.chip_concentration {
                    let chipPercent = chip * 100
                    VStack(alignment: .leading, spacing: 12) {
                        Text("筹码集中度")
                            .font(.headline)
                            .foregroundColor(.white)

                        HStack {
                            Gauge(value: chipPercent, in: 0...100) {
                                Text("CR指标")
                            } currentValueLabel: {
                                Text("\(Int(chipPercent))%")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            .gaugeStyle(.accessoryCircular)
                            .tint(chipColor(chipPercent))

                            VStack(alignment: .leading, spacing: 4) {
                                chipLabel(chipPercent)
                                Text(chipDescription(chipPercent))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.leading)
                        }
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .background(Color(hex: "121212"))
        .navigationTitle(stock.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // 估值颜色
    private func valuationColor(_ percentile: Double) -> Color {
        if percentile < 20 { return Color(hex: "4CAF50") }
        else if percentile < 50 { return Color(hex: "1E88E5") }
        else if percentile < 80 { return Color(hex: "FFC107") }
        else { return Color(hex: "F44336") }
    }

    // 估值标签
    private func valuationLabel(_ percentile: Double) -> some View {
        Group {
            if percentile < 20 { Text("极低估值") }
            else if percentile < 40 { Text("低估值") }
            else if percentile < 60 { Text("合理估值") }
            else if percentile < 80 { Text("高估值") }
            else { Text("极高估值") }
        }
        .font(.subheadline)
        .foregroundColor(valuationColor(percentile))
    }

    // 价格位置描述
    private func pricePositionDescription(_ percentile: Double) -> String {
        if percentile < 20 { return "历史低位，适合布局" }
        else if percentile < 40 { return "价格偏低，关注机会" }
        else if percentile < 60 { return "价格合理" }
        else if percentile < 80 { return "价格偏高，注意风险" }
        else { return "风险较大，谨慎参与" }
    }

    // 筹码颜色
    private func chipColor(_ value: Double) -> Color {
        if value > 80 { return Color(hex: "4CAF50") }
        else if value > 60 { return Color(hex: "1E88E5") }
        else if value > 40 { return Color(hex: "FFC107") }
        else { return Color(hex: "F44336") }
    }

    // 筹码标签
    private func chipLabel(_ value: Double) -> some View {
        Group {
            if value > 80 { Text("高度集中") }
            else if value > 60 { Text("相对集中") }
            else if value > 40 { Text("相对分散") }
            else { Text("高度分散") }
        }
        .font(.subheadline)
        .foregroundColor(chipColor(value))
    }

    // 筹码描述
    private func chipDescription(_ value: Double) -> String {
        if value > 80 { return "主力高度控盘，可能快速拉升" }
        else if value > 60 { return "筹码集中，上涨概率大" }
        else if value > 40 { return "筹码分布均衡" }
        else { return "筹码分散，上涨动力不足" }
    }
}
