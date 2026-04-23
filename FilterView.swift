import SwiftUI

struct FilterView: View {
    @EnvironmentObject var stockViewModel: StockViewModel
    @State private var selectedType = "全部"
    @State private var priceRange: Double = 100
    @State private var positionRange: Double = 30

    let types = ["全部", "A股", "ETF"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 股票类型
                VStack(alignment: .leading, spacing: 12) {
                    Text("股票类型")
                        .font(.headline)
                        .foregroundColor(.white)

                    HStack(spacing: 12) {
                        ForEach(types, id: \.self) { type in
                            Button(action: {
                                selectedType = type
                            }) {
                                Text(type)
                                    .font(.subheadline)
                                    .fontWeight(selectedType == type ? .semibold : .regular)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(selectedType == type ? Color(hex: "1E88E5") : Color(hex: "2C2C2C"))
                                    .foregroundColor(selectedType == type ? .white : .gray)
                                    .cornerRadius(20)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(hex: "1E1E1E"))
                .cornerRadius(12)

                // 股价范围
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("股价上限")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Text("¥\(Int(priceRange))")
                            .foregroundColor(Color(hex: "1E88E5"))
                    }

                    Slider(value: $priceRange, in: 1...200, step: 1)
                        .tint(Color(hex: "1E88E5"))
                }
                .padding()
                .background(Color(hex: "1E1E1E"))
                .cornerRadius(12)

                // 位置百分位
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("价格位置")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(Int(positionRange))%")
                            .foregroundColor(Color(hex: "1E88E5"))
                    }

                    Slider(value: $positionRange, in: 0...100, step: 5)
                        .tint(Color(hex: "1E88E5"))
                }
                .padding()
                .background(Color(hex: "1E1E1E"))
                .cornerRadius(12)

                // 筛选按钮
                Button(action: {
                    applyFilter()
                }) {
                    Text("应用筛选")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "1E88E5"))
                        .cornerRadius(12)
                }

                Spacer()
            }
            .padding()
        }
        .background(Color(hex: "121212"))
        .navigationTitle("筛选")
    }

    private func applyFilter() {
        // 筛选逻辑
    }
}

#Preview {
    NavigationStack {
        FilterView()
    }
    .environmentObject(StockViewModel())
    .preferredColorScheme(.dark)
}