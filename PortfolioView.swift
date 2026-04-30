import SwiftUI

struct PortfolioView: View {
    @EnvironmentObject var stockViewModel: StockViewModel
    @State private var showSellSheet = false
    @State private var selectedPosition: Position?
    @State private var sellQuantity = ""

    var body: some View {
        VStack(spacing: 0) {
            if stockViewModel.positionList.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("暂无持仓")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Text("在股票详情页点击买入添加持仓")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 总盈亏统计
                VStack(spacing: 8) {
                    Text("总盈亏")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    HStack {
                        Text(String(format: "%@¥%.2f", stockViewModel.totalReturn >= 0 ? "+" : "", stockViewModel.totalReturn))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(stockViewModel.totalReturn >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                        Text("(\(String(format: "%@%.1f%%", stockViewModel.totalReturnPct >= 0 ? "+" : "", stockViewModel.totalReturnPct)))")
                            .font(.headline)
                            .foregroundColor(stockViewModel.totalReturnPct >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(hex: "1E1E1E"))

                List {
                    ForEach(stockViewModel.positionList) { position in
                        VStack(alignment: .leading, spacing: 8) {
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
                                Button {
                                    showSellSheet = true
                                    selectedPosition = position
                                } label: {
                                    Text("卖出")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color(hex: "F44336"))
                                        .cornerRadius(6)
                                }
                            }

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(position.quantity)股")
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                    Text("¥\(String(format: "%.2f", position.currentPrice))")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("成本: ¥\(String(format: "%.2f", position.avgCost))")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    HStack(spacing: 4) {
                                        Text("盈亏:")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        Text(String(format: "%@%.1f%%", position.returnPct >= 0 ? "+" : "", position.returnPct))
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(position.returnPct >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.plain)
                .listRowBackground(Color(hex: "1E1E1E"))
            }
        }
        .background(Color(hex: "121212"))
        .navigationTitle("持仓")
        .onAppear {
            stockViewModel.updatePositionPrices()
        }
        .sheet(isPresented: $showSellSheet) {
            if let position = selectedPosition {
                SellSheetView(
                    position: position,
                    isPresented: $showSellSheet,
                    quantity: $sellQuantity
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        PortfolioView()
    }
    .environmentObject(StockViewModel())
    .preferredColorScheme(.dark)
}