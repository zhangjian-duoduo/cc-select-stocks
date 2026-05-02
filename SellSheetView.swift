import SwiftUI

struct SellSheetView: View {
    let position: Position
    @Binding var isPresented: Bool
    @Binding var quantity: String

    @EnvironmentObject var stockViewModel: StockViewModel

    // 获取最新价格
    private var currentPrice: Double {
        stockViewModel.allStocks.first(where: { $0.code == position.code })?.price ?? position.currentPrice
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 股票信息
                VStack(spacing: 4) {
                    Text(position.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text(position.code)
                        .foregroundColor(.gray)
                    if currentPrice > 0 {
                        Text("当前价格: ¥\(String(format: "%.2f", currentPrice))")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(hex: "1E1E1E"))
                .cornerRadius(12)

                // 持仓信息
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

                // 全卖按钮
                VStack(spacing: 8) {
                    Text("卖出数量(股):")
                        .foregroundColor(.gray)
                    TextField("100", text: $quantity)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color(hex: "1E1E1E"))
                .cornerRadius(8)

                Button {
                    if let qty = Int(quantity), qty >= 100, qty % 100 == 0, currentPrice > 0 {
                        if stockViewModel.sellStock(code: position.code, price: currentPrice, quantity: qty) {
                            isPresented = false
                        }
                    }
                } label: {
                    Text("确认卖出")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "F44336"))
                        .cornerRadius(12)
                }

                // 快速卖出选项
                HStack(spacing: 12) {
                    Button {
                        quantity = "100"
                    } label: {
                        Text("100")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "1E1E1E"))
                            .cornerRadius(6)
                    }

                    Button {
                        let half = (position.quantity / 200) * 100
                        if half >= 100 { quantity = String(half) }
                    } label: {
                        Text("1/2")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "1E1E1E"))
                            .cornerRadius(6)
                    }

                    Button {
                        quantity = String(position.quantity)
                    } label: {
                        Text("全部")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: "1E1E1E"))
                            .cornerRadius(6)
                    }
                }

                Spacer()
            }
            .padding()
            .background(Color(hex: "121212"))
            .navigationTitle("卖出")
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