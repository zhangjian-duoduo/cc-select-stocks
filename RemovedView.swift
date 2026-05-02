import SwiftUI

struct RemovedStock: Identifiable, Codable {
    var id: String { code + (removed_at ?? "") }
    let code: String
    let name: String
    let sector: String?
    let price: Double?
    let change_pct: Double?
    let removed_at: String?
}

struct RemovedResponse: Codable {
    let code: Int
    let data: [String: [RemovedStock]]?
    let message: String?
}

struct RemovedView: View {
    @EnvironmentObject var stockViewModel: StockViewModel
    @State private var removedData: [String: [RemovedStock]] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedDate: String?
    @State private var selectedStockIndex: Int = 0
    @State private var showDetailPage = false

    private let baseURL = AppConfig.baseURL

    var sortedDates: [String] {
        (removedData.keys).sorted(by: >)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 日期选择
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sortedDates, id: \.self) { date in
                        Button {
                            selectedDate = date
                        } label: {
                            VStack(spacing: 2) {
                                Text(formatDate(date))
                                    .font(.caption)
                                Text("\(removedData[date]?.count ?? 0)只")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedDate == date ? Color(hex: "1E88E5") : Color(hex: "1E1E1E"))
                            .foregroundColor(selectedDate == date ? .white : .gray)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }

            // 列表
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                Text("错误: \(error)")
                    .foregroundColor(.red)
                Spacer()
            } else if let date = selectedDate, let stocks = removedData[date] {
                List(stocks) { stock in
                    Button {
                        if let allIdx = stockViewModel.allStocks.firstIndex(where: { $0.code == stock.code }) {
                            selectedStockIndex = allIdx
                            showDetailPage = true
                        }
                    } label: {
                        RemovedStockRow(stock: stock)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowBackground(Color(hex: "1E1E1E"))
                }
                .listStyle(.plain)
            } else {
                Spacer()
                Text("选择日期查看")
                    .foregroundColor(.gray)
                Spacer()
            }
        }
        .background(Color(hex: "121212"))
        .navigationTitle("剔除股票")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showDetailPage) {
            if selectedStockIndex < stockViewModel.allStocks.count {
                StockDetailPageView(
                    currentIndex: selectedStockIndex,
                    allStocks: stockViewModel.allStocks,
                    currentPage: $selectedStockIndex
                )
            }
        }
        .onAppear {
            loadRemoved()
        }
    }

    private func formatDate(_ date: String) -> String {
        // 把 2026-04-20 变成 04-20
        let parts = date.split(separator: "-")
        if parts.count >= 2 {
            return "\(parts[1])-\(parts[2])"
        }
        return date
    }

    private func loadRemoved() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let result: RemovedResponse = try await APIClient.get("/removed")
                if result.code == 0, let data = result.data {
                    removedData = data
                    selectedDate = sortedDates.first
                } else {
                    errorMessage = result.message ?? "未知错误"
                }
            } catch let error as APIClient.APIError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct RemovedStockRow: View {
    let stock: RemovedStock

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(stock.name)
                        .font(.headline)
                        .foregroundColor(.white)
                    if let sector = stock.sector, !sector.isEmpty {
                        Text(sector)
                            .font(.caption)
                            .foregroundColor(Color(hex: "1E88E5"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "1E88E5").opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                Text(stock.code)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let price = stock.price {
                    Text(String(format: "%.2f", price))
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                if let change = stock.change_pct {
                    Text(String(format: "%+.2f%%", change))
                        .font(.caption)
                        .foregroundColor(change >= 0 ? Color(hex: "F44336") : Color(hex: "4CAF50"))
                }
            }
        }
        .padding(.vertical, 8)
    }
}