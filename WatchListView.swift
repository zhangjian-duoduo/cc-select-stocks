import SwiftUI

struct WatchListView: View {
    @EnvironmentObject var stockViewModel: StockViewModel

    var body: some View {
        VStack(spacing: 0) {
            if stockViewModel.favoritedStocks.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("暂无自选股票")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Text("点击股票卡片上的星标添加自选")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(stockViewModel.favoritedStocks) { stock in
                        NavigationLink(destination: StockDetailView(stock: stock)) {
                            WatchListCard(stock: stock)
                        }
                        .listRowBackground(Color(hex: "1E1E1E"))
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(hex: "121212"))
        .navigationTitle("自选")
    }
}

struct WatchListCard: View {
    let stock: Stock

    var body: some View {
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

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "¥%.2f", stock.price ?? 0))
                    .font(.headline)
                    .foregroundColor(.white)
                let changePct = stock.change_5y ?? 0
                Text(String(format: "%.2f%%", changePct))
                    .font(.caption)
                    .foregroundColor(changePct >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        WatchListView()
    }
    .environmentObject(StockViewModel())
    .preferredColorScheme(.dark)
}