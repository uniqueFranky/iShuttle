import SwiftUI
import Foundation
import UIKit
struct WeekDatePicker: View {
    @Binding var selectedDate: Date
    let calendar: Calendar

    private var dates: [Date] {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let mondayOffset = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: today) else { return [] }
        return (0..<14).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private var selectableRange: ClosedRange<Date> {
        let today = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 6, to: today) ?? today
        return today...end
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    let date = dates[index]
                    Text(calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { column in
                        let date = dates[row * 7 + column]
                        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                        let isSelectable = selectableRange.contains(date)
                        Button {
                            selectedDate = date
                        } label: {
                            Text(calendar.component(.day, from: date), format: .number)
                                .font(.subheadline.weight(isSelected ? .bold : .regular))
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(isSelected ? Color.accentColor : Color.clear, in: Circle())
                                .foregroundStyle(isSelected ? Color.white : (isSelectable ? Color.primary : Color.secondary.opacity(0.35)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!isSelectable)
                        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

