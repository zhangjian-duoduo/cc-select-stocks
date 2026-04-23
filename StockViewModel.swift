import Foundation
import Combine

enum SortOption: String, CaseIterable {
    case position = "位置"
    case score = "评分"
    case chip = "筹码"
    case shareholder = "股东"
    case bottomDivergence = "底背离"
}

class StockViewModel: ObservableObject {
    @Published var stocks: [Stock] = []
    @Published var filteredStocks: [Stock] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var sortOption: SortOption = .position
    @Published var sortAscending: Bool = false
    @Published var favorites: Set<String> = []

    private let baseURL = "http://8.163.91.16:5000/api/v1"

    init() {
        Task {
            await loadData()
        }
    }

    @MainActor
    func loadData() async {
        isLoading = true
        errorMessage = nil

        guard let url = URL(string: "\(baseURL)/stocks?page_size=50") else {
            errorMessage = "URL错误"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "无效响应"
                isLoading = false
                return
            }

            guard httpResponse.statusCode == 200 else {
                errorMessage = "服务器错误: \(httpResponse.statusCode)"
                isLoading = false
                return
            }

            let stockResponse = try JSONDecoder().decode(StockResponse.self, from: data)
            if stockResponse.code == 0 {
                self.stocks = stockResponse.data ?? []
                self.applySort()
                self.errorMessage = nil
            } else {
                self.errorMessage = "API错误: \(stockResponse.message ?? "未知错误")"
            }
        } catch let error as DecodingError {
            // 详细解析错误
            switch error {
            case .keyNotFound(let key, _):
                self.errorMessage = "缺少字段: \(key.stringValue)"
            case .typeMismatch(let type, _):
                self.errorMessage = "类型不匹配: \(type)"
            case .valueNotFound(let type, _):
                self.errorMessage = "值为空: \(type)"
            default:
                self.errorMessage = "数据解析错误: \(error.localizedDescription)"
            }
        } catch {
            self.errorMessage = "网络错误: \(error.localizedDescription)"
        }

        isLoading = false
    }

    @MainActor
    func refresh() async {
        await loadData()
    }

    func toggleSort(_ option: SortOption) {
        if sortOption == option {
            sortAscending.toggle()
        } else {
            sortOption = option
            sortAscending = false
        }
        applySort()
    }

    private func applySort() {
        let sorted = stocks.sorted { stock1, stock2 in
            let value1 = sortValue(for: stock1)
            let value2 = sortValue(for: stock2)
            return sortAscending ? value1 < value2 : value1 > value2
        }
        filteredStocks = sorted
    }

    private func sortValue(for stock: Stock) -> Double {
        switch sortOption {
        case .position:
            return stock.price_position ?? 1.0
        case .score:
            return calculateScore(stock)
        case .chip:
            return stock.chip_concentration ?? 0
        case .shareholder:
            guard let trend = stock.holders_trend, trend.count >= 2 else { return 0 }
            let recent = trend.suffix(3)
            let first = recent.first?.holders ?? 0
            let last = recent.last?.holders ?? 0
            return Double(first - last)
        case .bottomDivergence:
            return (stock.macd_divergence?.daily == true || stock.macd_divergence?.weekly == true || stock.macd_divergence?.monthly == true) ? 1 : 0
        }
    }

    private func calculateScore(_ stock: Stock) -> Double {
        let confidence = Double(trendConfidence(stock.trend_analysis)) / 100.0
        let chipVal = stock.chip_concentration ?? 50
        let chipScore = chipVal / 100.0
        let peVal = stock.pe_percentile ?? 50
        let valuationScore = 1.0 - (peVal / 100.0)
        let divergenceScore: Double = (stock.macd_divergence?.daily == true || stock.macd_divergence?.weekly == true || stock.macd_divergence?.monthly == true) ? 1.0 : 0.0
        return confidence * 0.4 + chipScore * 0.2 + valuationScore * 0.2 + divergenceScore * 0.2
    }

    private func trendConfidence(_ trend: Stock.TrendAnalysis?) -> Double {
        guard let t = trend else { return 50 }
        switch t.short {
        case "上升", "强": return 80
        case "横盘": return 50
        case "下降", "弱": return 20
        default: return 50
        }
    }

    // 自选股功能
    func isFavorited(_ code: String) -> Bool {
        return favorites.contains(code)
    }

    func toggleFavorite(_ stock: Stock) {
        if favorites.contains(stock.code) {
            favorites.remove(stock.code)
        } else {
            favorites.insert(stock.code)
        }
    }

    var favoritedStocks: [Stock] {
        stocks.filter { favorites.contains($0.code) }
    }
}