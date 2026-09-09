import SwiftUI
import Foundation
import UIKit
struct ReservationQRCodeView: View {
    let reservation: Reservation
    let service: ReservationService
    @Environment(\.dismiss) private var dismiss
    @State private var payload: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let payload {
                    Image(uiImage: QRCodeRenderer.image(for: payload))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(24)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(20)
                } else if let errorMessage {
                    ContentUnavailableView("二维码加载失败", systemImage: "qrcode", description: Text(errorMessage))
                } else {
                    ProgressView("正在加载二维码…")
                }
            }
            .navigationTitle(RouteLogic.displayRouteName(reservation.routeName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                do {
                    let resolved = try await service.qrCodeReservation(reservation)
                    payload = resolved.qrCodePayload
                } catch is CancellationError {
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

