import SwiftUI

// 交易弹窗视图
struct TradeSheetView: View {
    let stock: Stock
    @Binding var isPresented: Bool
    @Binding var selectedAction: Int
    @Binding var quantity: String

    @EnvironmentObject var stockViewModel: StockViewModel

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
                    if let price = stock.price {
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
                    VStack(spacing: 4) {
                        Text("当前持仓")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        HStack {
                            Text("\(position.quantity)股")
                                .foregroundColor(.white)
                            Text("成本: ¥\(String(format: "%.2f", position.avgCost))")
                                .foregroundColor(.gray)
                            Text("盈亏: \(String(format: "%@%.1f%%", position.returnPct >= 0 ? "+" : "", position.returnPct))")
                                .foregroundColor(position.returnPct >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
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

                // 确认按钮
                Button {
                    if let qty = Int(quantity), qty > 0, let price = stock.price {
                        if selectedAction == 0 {
                            // 买入
                            stockViewModel.buyStock(code: stock.code, name: stock.name, price: price, quantity: qty)
                        } else {
                            // 卖出
                            stockViewModel.sellStock(code: stock.code, price: price, quantity: qty)
                        }
                        isPresented = false
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