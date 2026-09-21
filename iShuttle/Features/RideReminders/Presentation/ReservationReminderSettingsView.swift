import SwiftUI

struct ReservationReminderSettingsView: View {
    let reservation: Reservation
    let globalSettings: RideReminderSettings
    let onSave: (Int?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var usesGlobalSetting: Bool
    @State private var advanceMinutes: Int
    @State private var isSaving = false

    init(
        reservation: Reservation,
        globalSettings: RideReminderSettings,
        preference: RideReminderPreference?,
        onSave: @escaping (Int?) async -> Void
    ) {
        self.reservation = reservation
        self.globalSettings = globalSettings
        self.onSave = onSave
        _usesGlobalSetting = State(initialValue: preference == nil)
        _advanceMinutes = State(initialValue: preference?.advanceMinutes ?? globalSettings.advanceMinutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("预约") {
                    LabeledContent("线路", value: RouteLogic.displayRouteName(reservation.routeName))
                    LabeledContent("发车时间", value: departureText)
                }

                Section {
                    Toggle("使用全局设置", isOn: $usesGlobalSetting)

                    if usesGlobalSetting {
                        LabeledContent("提醒时间", value: "提前\(globalSettings.advanceMinutes)分钟")
                    } else {
                        Stepper(
                            "提前\(advanceMinutes)分钟",
                            value: $advanceMinutes,
                            in: 1...60,
                            step: 1
                        )
                    }
                } header: {
                    Text("提醒时间")
                } footer: {
                    if globalSettings.enabled {
                        Text(usesGlobalSetting ? "该预约会跟随设置页中的默认提醒时间。" : "该时间只对本次预约生效。")
                    } else {
                        Text("乘车提醒当前已全局关闭。此处的配置会被保留，并在重新开启后生效。")
                    }
                }
            }
            .navigationTitle("预约提醒")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            isSaving = true
                            await onSave(usesGlobalSetting ? nil : advanceMinutes)
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private var departureText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M月d日 EEEE HH:mm"
        return formatter.string(from: reservation.departure)
    }
}
