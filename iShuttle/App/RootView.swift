import SwiftUI
import Foundation
import UIKit
struct RootView: View {
    @ObservedObject var container: AppContainer

    var body: some View {
        Group {
            if container.isAuthenticated {
                HomeView(container: container)
            } else {
                LoginView(container: container)
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .alert("需要重新登录", isPresented: Binding(
            get: { container.sessionMessage != nil },
            set: { if !$0 { container.sessionMessage = nil } }
        )) {
            Button("确定") { container.sessionMessage = nil }
        } message: {
            Text(container.sessionMessage ?? "")
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch container.settings.themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

struct HomeView: View {
    @ObservedObject var container: AppContainer

    var body: some View {
        TabView {
            QRHomeView(store: container.reservations, container: container)
                .tabItem { Label("乘车", systemImage: "qrcode") }
            ReservationView(store: container.reservations, container: container)
                .tabItem { Label("预约", systemImage: "calendar") }
            MyReservationsView(store: container.reservations, container: container)
                .tabItem { Label("我的预约", systemImage: "ticket") }
            SettingsView(container: container)
                .tabItem { Label("设置", systemImage: "gear") }
        }
    }
}

