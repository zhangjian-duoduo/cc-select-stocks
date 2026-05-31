import SwiftUI

struct SellSheetView: View {
    let position: Position
    @Binding var isPresented: Bool
    @Binding var quantity: String

    @EnvironmentObject var stockViewModel: StockViewModel
    @State private var errorMessage: String?

    private var currentPrice: Double {
        stockViewModel.latestPrice(for: position.code) ?? position.currentPrice
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // 股票信息
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(position.name)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(position.code)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("持仓 \(position.quantity)股")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("¥\(String(format: "%.2f", currentPrice))")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                .padding(12)
                .background(Color(hex: "2C2C2C"))
                .cornerRadius(8)

                // 卖出数量
                VStack(spacing: 8) {
                    Text("卖出数量（股）")
                        .font(.caption)
                        .foregroundColor(.gray)

                    HStack(spacing: 12) {
                        Button {
                            if let q = Int(quantity), q > 100 {
                                quantity = String(q - 100)
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                                .foregroundColor(.gray)
                        }

                        TextField("100", text: $quantity)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 100)

                        Button {
                            let q = Int(quantity) ?? 0
                            quantity = String(min(q + 100, position.quantity))
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 4)

                    // 快捷选择
                    HStack(spacing: 8) {
                        ForEach([("100", 100), ("1/2", position.quantity / 2), ("全部", position.quantity)], id: \.0) { label, raw in
                            let v = max(100, (raw / 100) * 100)
                            Button {
                                quantity = String(v)
                            } label: {
                                Text(label)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 5)
                                    .background(quantity == String(v) ? Color(hex: "1E88E5") : Color(hex: "3A3A3A"))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color(hex: "2C2C2C"))
                .cornerRadius(8)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Color(hex: "FF9800"))
                }

                // 预计回收
                HStack {
                    Text("预计回收")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Spacer()
                    let qty = Int(quantity) ?? 0
                    Text("¥\(String(format: "%.2f", currentPrice * Double(min(qty, position.quantity))))")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "4CAF50"))
                }
                .padding(12)
                .background(Color(hex: "2C2C2C"))
                .cornerRadius(8)

                Button {
                    errorMessage = nil
                    guard currentPrice > 0 else {
                        errorMessage = "无法获取当前价格"
                        return
                    }
                    guard let qty = Int(quantity) else {
                        errorMessage = "请输入有效的数字"
                        return
                    }
                    guard qty >= 100 else {
                        errorMessage = "最少卖出100股"
                        return
                    }
                    guard qty % 100 == 0 else {
                        errorMessage = "数量必须是100的整数倍"
                        return
                    }
                    guard qty <= 1000000 else {
                        errorMessage = "单笔不超过100万股"
                        return
                    }
                    guard qty <= position.quantity else {
                        errorMessage = "超出持仓数量(\(position.quantity)股)"
                        return
                    }
                    if stockViewModel.sellStock(code: position.code, price: currentPrice, quantity: qty) {
                        isPresented = false
                    }
                } label: {
                    Text("确认卖出")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color(hex: "F44336"))
                        .cornerRadius(8)
                }
            }
            .padding(16)
            .background(Color(hex: "1E1E1E"))
            .navigationTitle("卖出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        isPresented = false
                    }
                }
            }
            .onAppear {
                quantity = String(position.quantity)
            }
        }
    }
}
