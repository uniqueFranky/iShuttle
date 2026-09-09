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
                GeometryReader { proxy in
                    let horizontalPadding: CGFloat = 8
                    let squareSize = min(proxy.size.width - horizontalPadding * 2, proxy.size.height - horizontalPadding * 2)

                    VStack(spacing: 0) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                            .frame(width: squareSize, height: squareSize)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(reservation.routeName.replacingOccurrences(of: "→", with: " → "))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 20)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                            .background(.black)
                        Text(formattedDate(reservation.departure))
                            .font(.footnote)
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, horizontalPadding)
                    .offset(y: -15)
                }
            } else {
                ContentUnavailableView("暂无可用二维码", systemImage: "qrcode")
            }
        }
        .task { store.load() }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
