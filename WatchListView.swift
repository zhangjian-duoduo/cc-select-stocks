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
                            // 使用和选股列表相同的卡片
                            StockCard(stock: stock, sortOption: .position)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .listRowBackground(Color(hex: "1E1E1E"))
                    }
                }
                .listStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
            }
        }
        .background(Color(hex: "121212"))
        .navigationTitle("自选")
    }
}

#Preview {
    NavigationStack {
        WatchListView()
    }
    .environmentObject(StockViewModel())
    .preferredColorScheme(.dark)
}