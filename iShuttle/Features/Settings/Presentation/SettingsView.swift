import SwiftUI
import Foundation
import UIKit
struct SettingsView: View {
    @ObservedObject var container: AppContainer
    @State private var themeMode: String
    @State private var watchMaxReservationCount: Int
    @State private var watchExpirationMinutes: Double
    @State private var showingLogoutConfirmation = false

    init(container: AppContainer) {
        self.container = container
        _themeMode = State(initialValue: container.settings.themeMode)
        _watchMaxReservationCount = State(initialValue: container.settings.watchMaxReservationCount)
        _watchExpirationMinutes = State(initialValue: container.settings.watchExpirationMinutes)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(container.currentUsername() ?? "北京大学用户")
                                .font(.headline)
                            Text("已登录")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("外观") {
                    Picker("主题模式", selection: $themeMode) {
                        Text("跟随系统").tag("system")
                        Text("浅色模式").tag("light")
                        Text("深色模式").tag("dark")
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Apple Watch") {
                    Stepper("同步班次数：\(watchMaxReservationCount)", value: $watchMaxReservationCount, in: 1...10)
                    Stepper("班车过期时间：\(watchExpirationMinutes, specifier: "%.0f") 分钟", value: $watchExpirationMinutes, in: 1...60, step: 1)
                }

                Section {
                    Button(role: .destructive) {
                        showingLogoutConfirmation = true
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("设置")
            .onChange(of: watchMaxReservationCount) { _, value in
                Task { await container.updateWatchSettings(maxCount: value, expirationMinutes: watchExpirationMinutes) }
            }
            .onChange(of: watchExpirationMinutes) { _, value in
                Task { await container.updateWatchSettings(maxCount: watchMaxReservationCount, expirationMinutes: value) }
            }
            .onChange(of: themeMode) { _, value in
                container.updateThemeMode(value)
            }
            .confirmationDialog("确定要退出当前账号吗？", isPresented: $showingLogoutConfirmation, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    container.logout()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

