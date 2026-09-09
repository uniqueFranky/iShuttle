import SwiftUI
import Foundation
import UIKit
struct QRHomeView: View {
    let store: ReservationStore
    @ObservedObject var container: AppContainer
    @State private var reservation: Reservation?

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            Group {
            if let reservation {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最近的预约").font(.subheadline).foregroundStyle(.secondary)
                            Text(RouteLogic.displayRouteName(reservation.routeName)).font(.title2.bold())
                            Text(reservation.departure.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.green)
                    }
                    if let payload = reservation.qrCodePayload {
                        Image(uiImage: QRCodeRenderer.image(for: payload))
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(22)
                            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    Text("请在上车时出示此登记二维码")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(20)
            } else {
                ContentUnavailableView("暂无可用预约", systemImage: "bus")
            }
            }
        }
        .task {
            do {
                let refreshed = try await container.reservationService.refreshReservations()
                guard let latest = refreshed.first else {
                    reservation = nil
                    return
                }
                reservation = try await container.reservationService.qrCodeReservation(latest)
            } catch {
                if case APIError.authenticationRequired = error {
                    container.expireSession()
                }
            }
        }
    }

}

enum QRCodeRenderer {
    static func image(for payload: String) -> UIImage {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return UIImage()
        }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        let output = filter.outputImage ?? CIImage()
        let context = CIContext()
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return UIImage()
        }
        return UIImage(cgImage: cgImage)
    }
}

