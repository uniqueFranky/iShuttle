import SwiftUI
import Foundation
import UIKit
struct MyReservationsView: View {
    let store: ReservationStore
    @ObservedObject var container: AppContainer
    @StateObject private var viewModel: ReservationViewModel
    @State private var selectedReservation: Reservation?

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
                if viewModel.reservations.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView("暂无预约", systemImage: "ticket")
                } else {
                    List(viewModel.reservations) { reservation in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(departureText(for: reservation.departure))
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
                            Button(role: .destructive) {
                                Task { await viewModel.cancel(reservation) }
                            } label: {
                                Label("取消", systemImage: "trash")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("我的预约")
            .overlay { if viewModel.isLoading { ProgressView() } }
            .task { await viewModel.refreshReservations() }
            .refreshable { await viewModel.refreshReservations() }
            .sheet(item: $selectedReservation) { reservation in
                ReservationQRCodeView(reservation: reservation, service: container.reservationService)
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

