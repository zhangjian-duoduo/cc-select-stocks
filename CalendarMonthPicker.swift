import SwiftUI

/// 通用日历月份选择组件，FinancialUpdatesView 和 ChangesView 共用
struct CalendarMonthPicker: View {
    @Binding var displayedDate: Date
    @Binding var selectedDate: String
    @Binding var isExpanded: Bool

    /// 日期 -> 数量，nil 表示该日期无数据
    let dateData: [String: Int]

    let accentColor: Color
    let canGoNext: Bool
    let onMonthChanged: (String) -> Void
    let onDateSelected: (String) -> Void

    private let calendar = Calendar.current

    private var currentYearMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: displayedDate)
    }

    private var currentYear: Int {
        calendar.component(.year, from: displayedDate)
    }

    private var currentMonth: Int {
        calendar.component(.month, from: displayedDate)
    }

    private var daysOfMonth: [Int] {
        var components = DateComponents()
        components.year = currentYear
        components.month = currentMonth
        components.day = 1
        if let date = calendar.date(from: components),
           let range = calendar.range(of: .day, in: .month, for: date) {
            return Array(range)
        }
        return []
    }

    private var firstWeekdayOffset: Int {
        var components = DateComponents()
        components.year = currentYear
        components.month = currentMonth
        components.day = 1
        let firstDayOfMonth = calendar.date(from: components) ?? Date()
        return calendar.component(.weekday, from: firstDayOfMonth) - 1
    }

    private func makeDateString(_ day: Int) -> String {
        return String(format: "%04d-%02d-%02d", currentYear, currentMonth, day)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 月份导航
            HStack {
                Button {
                    goToPreviousMonth()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(Color(hex: "1E88E5"))
                        .padding(.trailing, 8)
                }

                Button {
                    onMonthChanged(currentYearMonth)
                } label: {
                    Text(currentYearMonth)
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(hex: "1E88E5"))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }

                Button {
                    goToNextMonth()
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(canGoNext ? Color(hex: "1E88E5") : .gray.opacity(0.3))
                        .padding(.leading, 8)
                }
                .disabled(!canGoNext)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
            .padding()

            // 日历网格
            if isExpanded {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                    Text("日").font(.caption).foregroundColor(.gray)
                    Text("一").font(.caption).foregroundColor(.gray)
                    Text("二").font(.caption).foregroundColor(.gray)
                    Text("三").font(.caption).foregroundColor(.gray)
                    Text("四").font(.caption).foregroundColor(.gray)
                    Text("五").font(.caption).foregroundColor(.gray)
                    Text("六").font(.caption).foregroundColor(.gray)

                    ForEach(Array(0..<firstWeekdayOffset).map { -$0 - 1 }, id: \.self) { _ in
                        Color.clear.frame(height: 40)
                    }

                    ForEach(daysOfMonth, id: \.self) { day in
                        let dateStr = makeDateString(day)
                        let hasData = dateData[dateStr] != nil
                        let count = dateData[dateStr] ?? 0

                        Button {
                            if hasData {
                                selectedDate = dateStr
                                onDateSelected(dateStr)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(day)")
                                    .font(.system(size: 14, weight: selectedDate == dateStr ? .bold : .regular))
                                if hasData && count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 9))
                                        .foregroundColor(accentColor)
                                } else {
                                    Text("-")
                                        .font(.system(size: 9))
                                        .foregroundColor(.gray.opacity(0.3))
                                }
                            }
                            .frame(height: 40)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(hasData
                                        ? (selectedDate == dateStr ? accentColor : Color(hex: "1E1E1E"))
                                        : Color(hex: "1E1E1E").opacity(0.3))
                            )
                            .foregroundColor(hasData ? (selectedDate == dateStr ? .black : .white) : .gray.opacity(0.3))
                        }
                        .disabled(!hasData)
                    }
                }
                .padding()
            }
        }
        .background(Color(hex: "1E1E1E"))
    }

    private func goToPreviousMonth() {
        if let newDate = calendar.date(byAdding: .month, value: -1, to: displayedDate) {
            displayedDate = newDate
            onMonthChanged(currentYearMonth)
        }
    }

    private func goToNextMonth() {
        guard canGoNext else { return }
        if let newDate = calendar.date(byAdding: .month, value: 1, to: displayedDate) {
            displayedDate = newDate
            onMonthChanged(currentYearMonth)
        }
    }
}
