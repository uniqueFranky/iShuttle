import SwiftUI
import Foundation
import UIKit
import SwiftUI
import Foundation
import UIKit
struct ReservationView: View {
    let store: ReservationStore
    @ObservedObject var container: AppContainer
    @State private var selectedDate = Date()
    @State private var selectedDirection: CommuteDirection = .toChangping
    @State private var locationDirectionApplied = false
    @State private var locationService = LocationDirectionService()
    @State private var locationToast: String?
    @StateObject private var viewModel: ReservationViewModel

    init(store: ReservationStore, container: AppContainer) {
        self.store = store
        self.container = container
        _viewModel = StateObject(wrappedValue: ReservationViewModel(
            service: container.reservationService,
            onAuthenticationRequired: { container.expireSession() }
        ))
    }

    private var beijingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    WeekDatePicker(
                        selectedDate: $selectedDate,
                        calendar: beijingCalendar
                    )
                        .onChange(of: selectedDate) { _, newDate in
                            Task {
                                await viewModel.refresh(
                                    on: newDate,
                                    calendar: beijingCalendar
                                )
                            }
                        }

                    if viewModel.isLoading {
                        ReservationLoadingView()
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else {

                        let relevantBuses = viewModel.buses.filter {
                            RouteLogic.direction(for: $0.routeName) != nil
                        }

                        let grouped = Dictionary(
                            grouping: relevantBuses,
                            by: { RouteLogic.direction(for: $0.routeName) }
                        )

                        let routeBuses = (grouped[selectedDirection] ?? [])
                            .sorted { $0.departure < $1.departure }

                        Picker("班车方向", selection: $selectedDirection) {
                            Text("海淀 → 昌平")
                                .tag(CommuteDirection.toChangping)

                            Text("昌平 → 海淀")
                                .tag(CommuteDirection.toHaidian)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("班车方向")

                        if routeBuses.isEmpty {
                            ContentUnavailableView(
                                selectedDateIsToday ? "今天已经没车了" : "当天没有班车",
                                systemImage: "bus"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                if routeBuses.contains(
                                    where: {
                                        RouteLogic.hasDelayedChangpingArrival(
                                            $0.routeName
                                        )
                                    }
                                ) {
                                    Label(
                                        "从200号校区出发的班车，到昌平晚约20分钟",
                                        systemImage: "clock.badge.exclamationmark"
                                    )
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 4)
                                    .padding(.bottom, 8)
                                }

                                ForEach(routeBuses) { bus in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(
                                                bus.departure.formatted(
                                                    date: .omitted,
                                                    time: .shortened
                                                )
                                            )
                                            .font(.title3.weight(.semibold))

                                            Text(
                                                RouteLogic.displayRouteName(
                                                    bus.routeName
                                                )
                                            )
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if let reservation = reservation(for: bus) {
                                            ReservationActionButton(
                                                title: "取消",
                                                isLoading: viewModel.isOperating(
                                                    reservation.id
                                                ),
                                                tint: .secondary,
                                                prominent: false
                                            ) {
                                                await viewModel.cancel(reservation)
                                            }
                                        } else {
                                            ReservationActionButton(
                                                title: "预约",
                                                isLoading: viewModel.isOperating(
                                                    bus.id
                                                ),
                                                tint: RouteLogic
                                                    .hasDelayedChangpingArrival(
                                                        bus.routeName
                                                    )
                                                    ? .orange
                                                    : .blue,
                                                prominent: true
                                            ) {
                                                await viewModel.reserve(
                                                    bus,
                                                    calendar: beijingCalendar
                                                )
                                            }
                                        }
                                    }
                                    .padding(14)
                                    .background(
                                        .background,
                                        in: RoundedRectangle(
                                            cornerRadius: 14,
                                            style: .continuous
                                        )
                                    )
                                    .padding(.bottom, 8)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } // ← ScrollView

            .navigationTitle("班车预约")
            .task {
                locationService.onDirection = { campus, direction in
                    guard !locationDirectionApplied else {
                        return
                    }

                    selectedDirection = direction
                    locationDirectionApplied = true

                    let directionName =
                        direction == .toChangping ? "去昌平" : "去海淀"

                    let message =
                        "已定位到" + campus + "，已设置为" + directionName

                    locationToast = message

                    Task {
                        try? await Task.sleep(for: .seconds(2))

                        if locationToast == message {
                            locationToast = nil
                        }
                    }
                }

                locationService.requestDirection()

                await viewModel.refresh(
                    on: selectedDate,
                    calendar: beijingCalendar
                )
            }
            .refreshable {
                await viewModel.refresh(
                    on: selectedDate,
                    calendar: beijingCalendar
                )
            }
            .alert(
                "操作失败",
                isPresented: Binding(
                    get: {
                        viewModel.errorMessage != nil
                    },
                    set: {
                        if !$0 {
                            viewModel.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("确定") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "未知错误")
            }
            .overlay(alignment: .top) {
                if let locationToast {
                    Label(
                        locationToast,
                        systemImage: "location.fill"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(
                        color: .black.opacity(0.15),
                        radius: 8,
                        y: 3
                    )
                    .padding(.top, 8)
                    .transition(
                        .move(edge: .top)
                            .combined(with: .opacity)
                    )
                }
            }
            .animation(
                .easeInOut(duration: 0.2),
                value: locationToast
            )
        }
    }

    private var selectedDateIsToday: Bool {
        beijingCalendar.isDate(selectedDate, inSameDayAs: Date())
    }

    private func reservation(for bus: BusOption) -> Reservation? {
        viewModel.reservations.first {
            $0.routeName == bus.routeName && abs($0.departure.timeIntervalSince(bus.departure)) < 60
        }
    }

}

struct ReservationActionButton: View {
    let title: String
    let isLoading: Bool
    let tint: Color
    let prominent: Bool
    let action: () async -> Void

    var body: some View {
        Group {
            if prominent {
                button.buttonStyle(.borderedProminent)
            } else {
                button.buttonStyle(.bordered)
            }
        }
        .tint(tint)
    }

    private var button: some View {
        Button { Task { await action() } } label: {
            Group {
                if isLoading { ProgressView() } else { Text(title) }
            }
            .frame(width: 78, height: 36)
        }
        .disabled(isLoading)
    }
}

struct ReservationLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.accentColor)
            Text("正在加载预约")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
