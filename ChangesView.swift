import SwiftUI

struct ChangeItem: Identifiable, Codable {
    var id: String { code }
    let code: String
    let name: String
    let type: String
}

struct ChangesResponse: Codable {
    let code: Int
    let data: ChangesData?
    let message: String?
}

struct ChangesData: Codable {
    let date: String
    let new: [ChangeItem]
    let removed: [ChangeItem]
    let new_count: Int
    let removed_count: Int
}

struct ChangesView: View {
    @State private var changesData: ChangesData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedTab = 0

    private let baseURL = "http://8.163.91.16:5000/api/v1"

    var body: some View {
        VStack(spacing: 0) {
            // 统计卡片
            if let data = changesData {
                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("\(data.new_count)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(Color(hex: "4CAF50"))
                        Text("新入选")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)

                    VStack(spacing: 4) {
                        Text("\(data.removed_count)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(Color(hex: "F44336"))
                        Text("已剔除")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "1E1E1E"))
                    .cornerRadius(12)
                }
                .padding()
            }

            // Tab选择
            Picker("类型", selection: $selectedTab) {
                Text("新入选 (\(changesData?.new_count ?? 0))").tag(0)
                Text("已剔除 (\(changesData?.removed_count ?? 0))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

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
            } else {
                List {
                    if selectedTab == 0 {
                        ForEach(changesData?.new ?? []) { item in
                            ChangeRow(item: item, isNew: true)
                                .listRowBackground(Color(hex: "1E1E1E"))
                        }
                    } else {
                        ForEach(changesData?.removed ?? []) { item in
                            ChangeRow(item: item, isNew: false)
                                .listRowBackground(Color(hex: "1E1E1E"))
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(hex: "121212"))
        .navigationTitle("每日变化")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadChanges()
        }
    }

    private func loadChanges() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                guard let url = URL(string: "\(baseURL)/changes") else {
                    errorMessage = "URL错误"
                    isLoading = false
                    return
                }

                let (data, response) = try await URLSession.shared.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    errorMessage = "服务器错误"
                    isLoading = false
                    return
                }

                let result = try JSONDecoder().decode(ChangesResponse.self, from: data)
                if result.code == 0, let data = result.data {
                    changesData = data
                } else {
                    errorMessage = result.message ?? "未知错误"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct ChangeRow: View {
    let item: ChangeItem
    let isNew: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(item.code)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            Image(systemName: isNew ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(isNew ? Color(hex: "4CAF50") : Color(hex: "F44336"))
                .font(.title2)
        }
        .padding(.vertical, 8)
    }
}
