import SwiftUI

struct ContentView: View {
    @EnvironmentObject var stockViewModel: StockViewModel

    var body: some View {
        TabView {
            NavigationStack {
                StockListView()
            }
            .tabItem {
                Label("选股", systemImage: "chart.line.uptrend.xyaxis")
            }

            NavigationStack {
                WatchListView()
            }
            .tabItem {
                Label("自选", systemImage: "star.fill")
            }

            NavigationStack {
                PortfolioView()
            }
            .tabItem {
                Label("持仓", systemImage: "chart.pie.fill")
            }

            NavigationStack {
                FilterView()
            }
            .tabItem {
                Label("筛选", systemImage: "slider.horizontal.3")
            }

            NavigationStack {
                FinancialUpdatesView()
            }
            .tabItem {
                Label("财务", systemImage: "dollarsign.circle")
            }

            NavigationStack {
                ChangesView()
            }
            .tabItem {
                Label("变化", systemImage: "arrow.left.arrow.right")
            }

            NavigationStack {
                RemovedView()
            }
            .tabItem {
                Label("剔除", systemImage: "trash")
            }
        }
        .tint(Color(hex: "1E88E5"))
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(StockViewModel())
}