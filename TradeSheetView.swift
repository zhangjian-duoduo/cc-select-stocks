import SwiftUI

// 交易弹窗视图
struct TradeSheetView: View {
    let stock: Stock
    @Binding var isPresented: Bool
    @Binding var selectedAction: Int
    @Binding var quantity: String

    @EnvironmentObject var stockViewModel: StockViewModel
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 股票信息
                VStack(spacing: 4) {
                    Text(stock.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text(stock.code)
                        .foregroundColor(.gray)
                    if let price = stockViewModel.latestPrice(for: stock.code) {
                        Text("当前价格: ¥\(String(format: "%.2f", price))")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(hex: "1E1E1E"))
                .cornerRadius(12)

                // 持仓信息
                if let position = stockViewModel.getPosition(stock.code) {
                    let currentPrice = stockViewModel.latestPrice(for: stock.code) ?? position.currentPrice
                    VStack(spacing: 4) {
                        Text("当前持仓")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        HStack {
                            Text("\(position.quantity)股")
                                .foregroundColor(.white)
                            Text("成本: ¥\(String(format: "%.2f", position.avgCost))")
                                .foregroundColor(.gray)
                            let rtn = position.realTimeReturnPct(currentPrice)
                            Text("盈亏: \(String(format: "%@%.1f%%", rtn >= 0 ? "+" : "", rtn))")
                                .foregroundColor(rtn >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                        }
                        .font(.headline)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }

                // 交易选项
                Picker("交易类型", selection: $selectedAction) {
                    Text("买入").tag(0)
                    Text("卖出").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                // 数量输入
                HStack {
                    Text("数量(股):")
                        .foregroundColor(.gray)
                    TextField("100", text: $quantity)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color(hex: "1E1E1E"))
                .cornerRadius(8)

                // 错误提示
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(Color(hex: "F44336"))
                        .font(.caption)
                }

                // 确认按钮
                Button {
                    errorMessage = nil
                    guard let qty = Int(quantity) else {
                        errorMessage = "请输入有效数量"
                        return
                    }
                    guard qty >= 100 else {
                        errorMessage = "最少交易100股"
                        return
                    }
                    guard qty % 100 == 0 else {
                        errorMessage = "数量必须为100的整数倍"
                        return
                    }
                    guard let price = stockViewModel.latestPrice(for: stock.code) else {
                        errorMessage = "无法获取当前价格"
                        return
                    }
                    if selectedAction == 0 {
                        stockViewModel.buyStock(code: stock.code, name: stock.name, price: price, quantity: qty)
                        isPresented = false
                    } else {
                        if stockViewModel.sellStock(code: stock.code, price: price, quantity: qty) {
                            isPresented = false
                        } else {
                            errorMessage = "持仓不足，无法卖出"
                        }
                    }
                } label: {
                    Text(selectedAction == 0 ? "确认买入" : "确认卖出")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedAction == 0 ? Color(hex: "4CAF50") : Color(hex: "F44336"))
                        .cornerRadius(12)
                }

                Spacer()
            }
            .padding()
            .background(Color(hex: "121212"))
            .navigationTitle(selectedAction == 0 ? "买入" : "卖出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        isPresented = false
                    }
                }
            }
        }
    }
}