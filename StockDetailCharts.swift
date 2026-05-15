import SwiftUI
import Charts

// MARK: - 子视图组件

extension StockDetailContent {

    @ViewBuilder
    func 股东趋势图(holders: [Stock.HolderData]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("股东人数趋势")
                .font(.headline)
                .foregroundColor(.white)

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
                }
            }
            .frame(height: 160)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .foregroundStyle(Color.gray)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let plotArea = geometry[proxy.plotAreaFrame]
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let xPos = value.location.x
                                    let cWidth = plotArea.width
                                    let xOff = plotArea.origin.x
                                    if holders.count > 0 {
                                        let idx = Int(((xPos - xOff) / cWidth) * CGFloat(holders.count))
                                        let clamped = max(0, min(idx, holders.count - 1))
                                        selectedQuarterIndex = clamped
                                    }
                                }
                                .onEnded { _ in }
                        )

                    if let index = selectedQuarterIndex, index < holders.count {
                        let hValue = Double(holders[index].holders ?? 0)
                        let cWidth = plotArea.width
                        let xOff = plotArea.origin.x
                        let xPos = xOff + (CGFloat(index) + 0.5) / CGFloat(holders.count) * cWidth

                        Path { path in
                            path.move(to: CGPoint(x: xPos, y: plotArea.origin.y))
                            path.addLine(to: CGPoint(x: xPos, y: plotArea.origin.y + plotArea.height))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundColor(Color.white.opacity(0.7))

                        let prices = holders.compactMap { Double($0.holders ?? 0) }
                        let minP = prices.min() ?? 0
                        let maxP = prices.max() ?? 1
                        if maxP > minP {
                            let ratio = (hValue - minP) / (maxP - minP)
                            let yPos = plotArea.origin.y + plotArea.height * (1 - ratio)

                            Path { path in
                                path.move(to: CGPoint(x: plotArea.origin.x, y: yPos))
                                path.addLine(to: CGPoint(x: plotArea.origin.x + plotArea.width, y: yPos))
                            }
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundColor(Color(hex: "1E88E5").opacity(0.7))
                        }
                    }
                }
            }

            if let index = selectedQuarterIndex, index < holders.count {
                HStack {
                    Text(holders[index].date ?? "")
                        .font(.caption)
                        .foregroundColor(.white)
                    Text(": \(holders[index].holders ?? 0)户")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "1E88E5"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: "1E1E1E"))
                .cornerRadius(8)
            }

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

    // 财务数据趋势图
    @ViewBuilder
    func 财务趋势图(history: [Stock.FinancialHistoryItem]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("净利润趋势")
                .font(.headline)
                .foregroundColor(.white)

            // 解析数据 - 按时间排序
            let sortedHistory = history.sorted { ($0.report_date ?? "") < ($1.report_date ?? "") }

            // 同比数据
            let yoyData = sortedHistory.compactMap { item -> (String, Double)? in
                guard let yoy = item.net_profit_yoy, !yoy.isEmpty else { return nil }
                let label = item.quarter ?? item.report_name ?? ""
                let value = Double(yoy.replacingOccurrences(of: "%", with: "")) ?? 0
                return (label, value)
            }

            // 环比数据
            let qoqData = sortedHistory.compactMap { item -> (String, Double)? in
                guard let qoq = item.net_profit_qoq, !qoq.isEmpty else { return nil }
                let label = item.quarter ?? item.report_name ?? ""
                let value = Double(qoq.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")) ?? 0
                return (label, value)
            }

            if yoyData.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                // 获取所有季度标签
                let allLabels = yoyData.map { $0.0 }

                // 同比趋势图
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(Color(hex: "4CAF50"))
                            .frame(width: 8, height: 8)
                        Text("同比 (YoY)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }

                    Chart {
                        ForEach(yoyData.indices, id: \.self) { index in
                            let item = yoyData[index]
                            LineMark(
                                x: .value("季度", item.0),
                                y: .value("同比", item.1)
                            )
                            .foregroundStyle(Color(hex: "4CAF50"))

                            PointMark(
                                x: .value("季度", item.0),
                                y: .value("同比", item.1)
                            )
                            .foregroundStyle(Color(hex: "4CAF50"))
                        }
                    }
                    .frame(height: 140)
                    .chartXAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisValueLabel()
                                .font(.caption2)
                                .foregroundStyle(Color.gray)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisValueLabel()
                                .foregroundStyle(Color.gray)
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            let plotArea = geometry[proxy.plotAreaFrame]
                            let cWidth = plotArea.width
                            let xOff = plotArea.origin.x

                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let xPos = value.location.x
                                            if allLabels.count > 0 {
                                                let idx = Int(((xPos - xOff) / cWidth) * CGFloat(allLabels.count))
                                                selectedFinancialIndex = max(0, min(idx, allLabels.count - 1))
                                            }
                                        }
                                )

                            // 十字线
                            if let idx = selectedFinancialIndex, idx < allLabels.count {
                                let xPos = xOff + (CGFloat(idx) + 0.5) / CGFloat(allLabels.count) * cWidth
                                Path { path in
                                    path.move(to: CGPoint(x: xPos, y: plotArea.origin.y))
                                    path.addLine(to: CGPoint(x: xPos, y: plotArea.origin.y + plotArea.height))
                                }
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundColor(Color.white.opacity(0.7))
                            }
                        }
                    }

                    // 同比数值
                    if let idx = selectedFinancialIndex, idx < yoyData.count {
                        let item = yoyData[idx]
                        Text("\(item.0): \(String(format: "%.1f%%", item.1))")
                            .font(.caption)
                            .foregroundColor(Color(hex: "4CAF50"))
                    }
                }
                .padding()
                .background(Color(hex: "1E1E1E"))
                .cornerRadius(8)

                // 环比趋势图
                if !qoqData.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle()
                                .fill(Color(hex: "FFEB3B"))
                                .frame(width: 8, height: 8)
                            Text("环比 (QoQ)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }

                        let qoqLabels = qoqData.map { $0.0 }

                        Chart {
                            ForEach(qoqData.indices, id: \.self) { index in
                                let item = qoqData[index]
                                LineMark(
                                    x: .value("季度", item.0),
                                    y: .value("环比", item.1)
                                )
                                .foregroundStyle(Color(hex: "FFEB3B"))

                                PointMark(
                                    x: .value("季度", item.0),
                                    y: .value("环比", item.1)
                                )
                                .foregroundStyle(Color(hex: "FFEB3B"))
                            }
                        }
                        .frame(height: 140)
                        .chartXAxis {
                            AxisMarks(values: .automatic) { _ in
                                AxisValueLabel()
                                    .font(.caption2)
                                    .foregroundStyle(Color.gray)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in
                                AxisValueLabel()
                                    .foregroundStyle(Color.gray)
                            }
                        }
                        .chartOverlay { proxy in
                            GeometryReader { geometry in
                                let plotArea = geometry[proxy.plotAreaFrame]
                                let cWidth = plotArea.width
                                let xOff = plotArea.origin.x

                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                let xPos = value.location.x
                                                if qoqLabels.count > 0 {
                                                    let idx = Int(((xPos - xOff) / cWidth) * CGFloat(qoqLabels.count))
                                                    selectedFinancialIndex = max(0, min(idx, qoqLabels.count - 1))
                                                }
                                            }
                                    )

                                if let idx = selectedFinancialIndex, idx < qoqLabels.count {
                                    let xPos = xOff + (CGFloat(idx) + 0.5) / CGFloat(qoqLabels.count) * cWidth
                                    Path { path in
                                        path.move(to: CGPoint(x: xPos, y: plotArea.origin.y))
                                        path.addLine(to: CGPoint(x: xPos, y: plotArea.origin.y + plotArea.height))
                                    }
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .foregroundColor(Color.white.opacity(0.7))
                                }
                            }
                        }

                        // 环比数值
                        if let idx = selectedFinancialIndex, idx < qoqData.count {
                            let item = qoqData[idx]
                            Text("\(item.0): \(String(format: "%.1f%%", item.1))")
                                .font(.caption)
                                .foregroundColor(Color(hex: "FFEB3B"))
                        }
                    }
                    .padding()
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(hex: "1E1E1E"))
        .cornerRadius(12)
    }

    @ViewBuilder
    func k线趋势图(kline: [Stock.KlineData]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("股价趋势（\(selectedKlinePeriod.rawValue)线）")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }

            HStack(spacing: 12) {
                ForEach(StockDetailPageView.KlinePeriod.allCases, id: \.self) { period in
                    Button {
                        selectedKlinePeriod = period
                        selectedKlineIndex = nil
                    } label: {
                        Text(period.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedKlinePeriod == period ? .semibold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(selectedKlinePeriod == period ? Color(hex: "1E88E5") : Color(hex: "2C2C2C"))
                            .foregroundColor(selectedKlinePeriod == period ? .white : .gray)
                            .cornerRadius(16)
                    }
                }
            }

            Chart {
                ForEach(kline.indices, id: \.self) { index in
                    LineMark(
                        x: .value("日期", index),
                        y: .value("收盘价", kline[index].close ?? 0)
                    )
                    .foregroundStyle(Color(hex: "FFC107"))

                    if let selectedIdx = selectedKlineIndex, selectedIdx == index {
                        PointMark(
                            x: .value("日期", index),
                            y: .value("收盘价", kline[index].close ?? 0)
                        )
                        .foregroundStyle(Color.white)
                        .symbolSize(80)
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisValueLabel()
                        .foregroundStyle(Color.gray)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let plotArea = geometry[proxy.plotAreaFrame]

                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let xPos = value.location.x
                                    let cWidth = plotArea.width
                                    let xOff = plotArea.origin.x
                                    if kline.count > 0 {
                                        let idx = Int(((xPos - xOff) / cWidth) * CGFloat(kline.count))
                                        let clamped = max(0, min(idx, kline.count - 1))
                                        selectedKlineIndex = clamped
                                    }
                                }
                                .onEnded { _ in }
                        )

                    if let index = selectedKlineIndex, index < kline.count {
                        let price = Double(kline[index].close ?? 0)
                        let cWidth = plotArea.width
                        let xOff = plotArea.origin.x
                        let xPos = xOff + (CGFloat(index) + 0.5) / CGFloat(kline.count) * cWidth

                        Path { path in
                            path.move(to: CGPoint(x: xPos, y: plotArea.origin.y))
                            path.addLine(to: CGPoint(x: xPos, y: plotArea.origin.y + plotArea.height))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundColor(Color.white.opacity(0.7))

                        let prices = kline.compactMap { Double($0.close ?? 0) }
                        let minP = prices.min() ?? 0
                        let maxP = prices.max() ?? 1
                        if maxP > minP {
                            let ratio = (price - minP) / (maxP - minP)
                            let yPos = plotArea.origin.y + plotArea.height * (1 - ratio)

                            Path { path in
                                path.move(to: CGPoint(x: plotArea.origin.x, y: yPos))
                                path.addLine(to: CGPoint(x: plotArea.origin.x + plotArea.width, y: yPos))
                            }
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundColor(Color(hex: "FFC107").opacity(0.7))
                        }
                    }
                }
            }

            if let index = selectedKlineIndex, index < kline.count {
                let data = kline[index]
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(data.date ?? "")
                            .font(.caption)
                            .foregroundColor(.gray)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading) {
                                Text("开")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                                Text(String(format: "%.2f", data.open ?? 0))
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                            VStack(alignment: .leading) {
                                Text("高")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                                Text(String(format: "%.2f", data.high ?? 0))
                                    .font(.caption)
                                    .foregroundColor(Color(hex: "F44336"))
                            }
                            VStack(alignment: .leading) {
                                Text("低")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                                Text(String(format: "%.2f", data.low ?? 0))
                                    .font(.caption)
                                    .foregroundColor(Color(hex: "4CAF50"))
                            }
                            VStack(alignment: .leading) {
                                Text("收")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                                Text(String(format: "%.2f", data.close ?? 0))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                            VStack(alignment: .leading) {
                                Text("量")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                                Text(formatVolume(data.volume ?? 0))
                                    .font(.caption)
                                    .foregroundColor(Color(hex: "FFC107"))
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(hex: "2C2C2C"))
                .cornerRadius(8)
            } else {
                HStack {
                    Text("最新: ")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(String(format: "¥%.2f", kline.last?.close ?? 0))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Spacer()
                    if kline.count >= 2 {
                        let change = ((kline.last?.close ?? 0) - (kline.first?.close ?? 0)) / (kline.first?.close ?? 1) * 100
                        Text("累计: \(String(format: "%.1f%%", change))")
                            .font(.caption)
                            .foregroundColor(change >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                    }
                }
            }
        }
        .padding()
        .background(Color(hex: "1E1E1E"))
        .cornerRadius(12)
    }

    @ViewBuilder
    func 价格分位View(pricePct: Double) -> some View {
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

    @ViewBuilder
    func PE百分位View(peTTM: Double, pePct: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PE 估值分析")
                .font(.headline)
                .foregroundColor(.white)

            HStack {
                Gauge(value: pePct, in: 0...100) {
                    Text("PE分位")
                } currentValueLabel: {
                    Text("\(Int(pePct))%")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(valuationColor(pePct))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("PE-TTM")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Text(String(format: "%.2f", peTTM))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    Text(pePositionDescription(pePct))
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

    func pePositionDescription(_ percentile: Double) -> String {
        if percentile < 20 { return "PE处历史低位，估值偏低" }
        else if percentile < 40 { return "PE偏低，估值合理偏低" }
        else if percentile < 60 { return "PE处历史中位，估值合理" }
        else if percentile < 80 { return "PE偏高，估值偏贵" }
        else { return "PE处历史高位，估值过高" }
    }

    @ViewBuilder
    func 趋势分析View(trend: Stock.TrendAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("趋势分析")
                .font(.headline)
                .foregroundColor(.white)

            HStack {
                趋势标签(title: "短期", value: trend.short)
                Spacer()
                趋势标签(title: "中期", value: trend.medium)
                Spacer()
                趋势标签(title: "长期", value: trend.long)
            }
        }
        .padding()
        .background(Color(hex: "1E1E1E"))
        .cornerRadius(12)
    }

    @ViewBuilder
    func 趋势标签(title: String, value: String?) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
            趋势图标(value: value ?? "-")
            Text(趋势文字(value: value ?? "-"))
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    @ViewBuilder
    func 趋势图标(value: String) -> some View {
        switch value {
        case "上涨趋势":
            Image(systemName: "arrow.up.right")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(hex: "FF5252"))
        case "下跌趋势":
            Image(systemName: "arrow.down.right")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(hex: "4CAF50"))
        default:
            Image(systemName: "minus")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(hex: "FFEB3B"))
        }
    }

    func 趋势文字(value: String) -> String {
        switch value {
        case "上涨趋势": return "上涨"
        case "下跌趋势": return "下跌"
        case "震荡筑底", "长期筑底": return "筑底"
        case "震荡": return "震荡"
        default: return "未知"
        }
    }

    @ViewBuilder
    func 筹码集中度View(chip: Double) -> some View {
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

    // MARK: - 辅助函数

    func valuationColor(_ percentile: Double) -> Color {
        if percentile < 20 { return Color(hex: "4CAF50") }
        else if percentile < 50 { return Color(hex: "1E88E5") }
        else if percentile < 80 { return Color(hex: "FFC107") }
        else { return Color(hex: "F44336") }
    }

    func pricePositionDescription(_ percentile: Double) -> String {
        if percentile < 20 { return "历史低位，适合布局" }
        else if percentile < 40 { return "价格偏低，关注机会" }
        else if percentile < 60 { return "价格合理" }
        else if percentile < 80 { return "价格偏高，注意风险" }
        else { return "风险较大，谨慎参与" }
    }

    func chipColor(_ value: Double) -> Color {
        if value > 80 { return Color(hex: "4CAF50") }
        else if value > 60 { return Color(hex: "1E88E5") }
        else if value > 40 { return Color(hex: "FFC107") }
        else { return Color(hex: "F44336") }
    }

    func chipLabel(_ value: Double) -> some View {
        Group {
            if value > 80 { Text("高度集中") }
            else if value > 60 { Text("相对集中") }
            else if value > 40 { Text("相对分散") }
            else { Text("高度分散") }
        }
        .font(.subheadline)
        .foregroundColor(chipColor(value))
    }

    func chipDescription(_ value: Double) -> String {
        if value > 80 { return "主力高度控盘，可能快速拉升" }
        else if value > 60 { return "筹码集中，上涨概率大" }
        else if value > 40 { return "筹码分布均衡" }
        else { return "筹码分散，上涨动力不足" }
    }

    func conceptLabelColor(_ index: Int) -> String {
        let colors = ["4FC3F7", "AED581", "FFB74D", "CE93D8", "EF5350",
                      "26C6DA", "9CCC65", "FFA726", "AB47BC", "42A5F5"]
        return colors[index % colors.count]
    }

    func formatVolume(_ volume: Double) -> String {
        if volume >= 100000000 {
            return String(format: "%.2f亿", volume / 100000000)
        } else if volume >= 10000 {
            return String(format: "%.2f万", volume / 10000)
        } else {
            return String(format: "%.0f", volume)
        }
    }
}
