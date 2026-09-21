import SwiftUI
import Foundation
import UIKit
struct MyReservationsView: View {
    let store: ReservationStore
    @ObservedObject var container: AppContainer
    @StateObject private var viewModel: ReservationViewModel
    @State private var selectedReservation: Reservation?
    @State private var reminderReservation: Reservation?

    init(store: ReservationStore, container: AppContainer) {
        self.store = store
        self.container = container
        _viewModel = StateObject(wrappedValue: ReservationViewModel(
            service: container.reservationService,
            onAuthenticationRequired: { container.expireSession() }
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ReservationLoadingView()
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else if viewModel.reservations.isEmpty {
                    ContentUnavailableView("暂无预约", systemImage: "ticket")
                } else {
                    List(viewModel.reservations) { reservation in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(viewModel.isOperating(reservation.id) ? "正在取消" : departureText(for: reservation.departure))
                                    .font(.headline)
                                Text(RouteLogic.displayRouteName(reservation.routeName))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedReservation = reservation }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                selectedReservation = reservation
                            } label: {
                                Label("二维码", systemImage: "qrcode")
                            }
                            .tint(.blue)
                            Button {
                                reminderReservation = reservation
                            } label: {
                                Label("提醒", systemImage: "bell")
                            }
                            .tint(.orange)
                            Button(role: .destructive) {
                                Task { await viewModel.cancel(reservation) }
                            } label: {
                                if viewModel.isOperating(reservation.id) {
                                    ProgressView()
                                } else {
                                    Label("取消", systemImage: "trash")
                                }
                            }
                            .disabled(viewModel.isOperating(reservation.id))
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("我的预约")
            .overlay(alignment: .top) {
                if let toastMessage = viewModel.toastMessage {
                    Text(toastMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.toastMessage)
            .onChange(of: viewModel.toastMessage) { _, message in
                guard message != nil else { return }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if viewModel.toastMessage == message {
                        viewModel.toastMessage = nil
                    }
                }
            }
            .task { await viewModel.refreshReservations() }
            .refreshable { await viewModel.refreshReservations() }
            .sheet(item: $selectedReservation) { reservation in
                ReservationQRCodeView(reservation: reservation, service: container.reservationService)
            }
            .sheet(item: $reminderReservation) { reservation in
                ReservationReminderSettingsView(
                    reservation: reservation,
                    globalSettings: RideReminderSettings(
                        enabled: container.settings.rideReminderEnabled,
                        advanceMinutes: container.settings.rideReminderAdvanceMinutes
                    ),
                    preference: container.rideReminderPreference(for: reservation)
                ) { advanceMinutes in
                    await container.updateRideReminderPreference(
                        advanceMinutes: advanceMinutes,
                        for: reservation
                    )
                }
            }
            .alert("操作失败", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) { Button("确定") { viewModel.errorMessage = nil } } message: {
                Text(viewModel.errorMessage ?? "未知错误")
            }
        }
    }

    private func departureText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M月d日 EEEE HH:mm"
        return formatter.string(from: date)
    }
}
