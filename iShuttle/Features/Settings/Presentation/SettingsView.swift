import SwiftUI
import Foundation
import UIKit
struct SettingsView: View {
    @ObservedObject var container: AppContainer
    @State private var themeMode: String
    @State private var watchMaxReservationCount: Int
    @State private var watchExpirationMinutes: Double
    @State private var rideReminderEnabled: Bool
    @State private var rideReminderAdvanceMinutes: Int
    @State private var isSyncingWatch = false
    @State private var watchSyncMessage: String?
    @State private var showingLogoutConfirmation = false

    init(container: AppContainer) {
        self.container = container
        _themeMode = State(initialValue: container.settings.themeMode)
        _watchMaxReservationCount = State(initialValue: container.settings.watchMaxReservationCount)
        _watchExpirationMinutes = State(initialValue: container.settings.watchExpirationMinutes)
        _rideReminderEnabled = State(initialValue: container.settings.rideReminderEnabled)
        _rideReminderAdvanceMinutes = State(initialValue: container.settings.rideReminderAdvanceMinutes)
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

                Section("班车预约") {
                    Stepper("预约过期时间：\(watchExpirationMinutes, specifier: "%.0f") 分钟", value: $watchExpirationMinutes, in: 1...60, step: 1)
                }

                Section("乘车提醒") {
                    Toggle("启用乘车提醒", isOn: $rideReminderEnabled)
                        .disabled(container.rideReminderAuthorization == .denied)
                    if container.rideReminderAuthorization == .denied {
                        Text("系统通知权限未开启，乘车提醒已关闭")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("去系统设置开启") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                    } else if rideReminderEnabled && container.rideReminderAuthorization == .authorized {
                        Stepper(
                            "默认提前时长：\(rideReminderAdvanceMinutes) 分钟",
                            value: $rideReminderAdvanceMinutes,
                            in: 1...60,
                            step: 1
                        )
                    }
                }

                Section("Apple Watch") {
                    Stepper("最大同步预约数量：\(watchMaxReservationCount)", value: $watchMaxReservationCount, in: 1...10)

                    Button {
                        Task {
                            isSyncingWatch = true
                            let result = await container.syncWatchData()
                            isSyncingWatch = false
                            watchSyncMessage = result.displayMessage
                            try? await Task.sleep(for: .seconds(2))
                            watchSyncMessage = nil
                        }
                    } label: {
                        HStack {
                            Label("主动同步数据", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if isSyncingWatch {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSyncingWatch)
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
            .overlay(alignment: .top) {
                if let watchSyncMessage {
                    Text(watchSyncMessage)
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
            .animation(.easeInOut(duration: 0.2), value: watchSyncMessage)
            .onChange(of: container.settings) { _, value in
                themeMode = value.themeMode
                watchMaxReservationCount = value.watchMaxReservationCount
                watchExpirationMinutes = value.watchExpirationMinutes
                rideReminderEnabled = value.rideReminderEnabled
                rideReminderAdvanceMinutes = value.rideReminderAdvanceMinutes
            }
            .onChange(of: watchMaxReservationCount) { _, value in
                Task { await container.updateWatchSettings(maxCount: value, expirationMinutes: watchExpirationMinutes) }
            }
            .onChange(of: watchExpirationMinutes) { _, value in
                Task { await container.updateWatchSettings(maxCount: watchMaxReservationCount, expirationMinutes: value) }
            }
            .onChange(of: themeMode) { _, value in
                container.updateThemeMode(value)
            }
            .onChange(of: rideReminderEnabled) { _, value in
                Task { await container.updateRideReminderSettings(enabled: value, advanceMinutes: rideReminderAdvanceMinutes) }
            }
            .onChange(of: rideReminderAdvanceMinutes) { _, value in
                guard value > 0 else { return }
                Task { await container.updateRideReminderSettings(enabled: rideReminderEnabled, advanceMinutes: value) }
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
