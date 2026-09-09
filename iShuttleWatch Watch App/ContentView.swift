//
//  ContentView.swift
//  iShuttleWatch Watch App
//
//  Created by 闫润邦 on 2026/9/9.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var store: WatchReservationStore

    var body: some View {
        Group {
            if let reservation = store.reservation,
               let imageData = reservation.qrCodeImageData,
               let image = UIImage(data: imageData) {
                VStack(spacing: 8) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .background(.white)
                    Text(reservation.routeName.replacingOccurrences(of: "→", with: " → "))
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                    Text(reservation.departure, format: .dateTime.month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            } else {
                ContentUnavailableView("暂无可用二维码", systemImage: "qrcode")
            }
        }
        .task { store.load() }
    }
}
