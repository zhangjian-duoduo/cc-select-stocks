import SwiftUI

// 退市风险分析视图
struct 退市风险分析View: View {
    let stock: Stock

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(hex: "FFEB3B"))
                Text("退市风险分析")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            // 风险规则列表
            VStack(spacing: 8) {
                ForEach(analyzeRisks(), id: \.rule) { item in
                    HStack {
                        // 规则名称
                        Text(item.rule)
                            .font(.subheadline)
                            .foregroundColor(.white)

                        Spacer()

                        // 状态标签
                        Text(item.status)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(backgroundColor(for: item.status))
                            .cornerRadius(4)

                        // 详情
                        Text(item.detail)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 160, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(hex: "1E1E1E"))
        .cornerRadius(12)
    }

    private func analyzeRisks() -> [(rule: String, status: String, detail: String)] {
        var results: [(rule: String, status: String, detail: String)] = []
        let code = stock.code
        let isGEM = code.hasPrefix("30")
        let isSTAR = code.hasPrefix("68")

        // ===== 财务类规则 =====

        // 1. 净利润为负且营收低于门槛
        let profitNegative = checkProfitNegative()
        let revenueLow = checkRevenueLow(isGEM: isGEM, isSTAR: isSTAR)

        if profitNegative && revenueLow {
            let riskDetail: String
            if isSTAR {
                riskDetail = "(科创板) 净利润为负 + 营收<5000万"
            } else if isGEM {
                riskDetail = "(创业板) 净利润为负 + 营收<1亿"
            } else {
                riskDetail = "(主板) 净利润为负 + 营收<3亿"
            }
            results.append((rule: "净利润为负且营收低于门槛", status: "危险", detail: riskDetail))
        } else if profitNegative {
            results.append((rule: "净利润为负", status: "警示", detail: "净利润为负，但营收尚在门槛之上"))
        }

        // 2. 净资产为负 (暂无字段，先使用默认)
        // 如有 net_asset 字段可启用

        // 3. 审计意见 (暂无字段)

        // ===== 交易类规则 =====

        // 4. 收盘价低于1元 (面值退市)
        if let price = stock.price, price < 1.0 {
            results.append((rule: "收盘价低于1元", status: "危险", detail: "连续20个交易日将触发面值退市"))
        } else if let price = stock.price, price < 1.5 {
            results.append((rule: "收盘价低于1元", status: "警示", detail: "当前价格 \(String(format: "%.2f", price))元，低于1.5元警戒线"))
        }

        // 5. 市值低于3亿
        // 市值用 market_cap 字段
        if let marketCap = stock.total_market_cap {
            if marketCap < 300000000 {
                results.append((rule: "市值低于3亿", status: "危险", detail: "连续20个交易日将触发市值退市"))
            } else if marketCap < 500000000 {
                results.append((rule: "市值低于3亿", status: "警示", detail: "当前市值 \(String(format: "%.2f", marketCap / 100000000))亿，低于5亿警戒线"))
            }
        }

        // 6. 股价低于2元
        if let price = stock.price, price < 2.0 {
            results.append((rule: "股价低于2元", status: "警示", detail: "当前价格 \(String(format: "%.2f", price))元，低价股风险高"))
        }

        // 7. 股东人数不达标 (暂无准确数据)
        // 科创板: >= 400人, 其他: >= 2000人

        // ===== 规范类规则 =====

        // 8. ST股票标识
        if stock.name.hasPrefix("ST") || stock.name.hasPrefix("*ST") {
            if stock.name.hasPrefix("*ST") {
                results.append((rule: "退市风险警示", status: "危险", detail: "*ST股票，已触发退市风险警示"))
            } else {
                results.append((rule: "ST股票", status: "警示", detail: "ST股票，存在退市风险"))
            }
        }

        if results.isEmpty {
            results.append((rule: "综合评估", status: "安全", detail: "未发现明显退市风险信号"))
        }

        return results
    }

    // 检查净利润是否为负
    private func checkProfitNegative() -> Bool {
        guard let yoy = stock.net_profit_yoy else { return false }
        let clean = yoy.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")
        guard let value = Double(clean) else { return false }
        return value < 0
    }

    // 检查营收是否低于门槛
    private func checkRevenueLow(isGEM: Bool, isSTAR: Bool) -> Bool {
        guard let revenue = stock.revenue else { return false }

        // revenue格式可能是 "123.45亿" 或 "1234.56万"
        let numStr = revenue.replacingOccurrences(of: "亿", with: "").replacingOccurrences(of: "万", with: "").replacingOccurrences(of: "元", with: "")
        guard let num = Double(numStr) else { return false }

        var revenueInYuan: Double = num
        if revenue.contains("万") {
            revenueInYuan = num * 10000
        } else if revenue.contains("亿") {
            revenueInYuan = num * 100000000
        }

        // 判断是否低于门槛
        let threshold: Double
        if isSTAR {
            threshold = 50000000  // 5000万
        } else if isGEM {
            threshold = 100000000  // 1亿
        } else {
            threshold = 300000000  // 3亿
        }

        return revenueInYuan < threshold
    }

    private func backgroundColor(for status: String) -> Color {
        switch status {
        case "安全":
            return Color(hex: "4CAF50")
        case "警示":
            return Color(hex: "FFEB3B")
        case "危险":
            return Color(hex: "F44336")
        case "未知":
            return Color(hex: "757575")
        default:
            return Color.gray
        }
    }
}
