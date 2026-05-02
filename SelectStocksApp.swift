import SwiftUI

@main
struct SelectStocksApp: App {
    @StateObject private var stockViewModel = StockViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(stockViewModel)
                .preferredColorScheme(.dark)
        }
    }
}