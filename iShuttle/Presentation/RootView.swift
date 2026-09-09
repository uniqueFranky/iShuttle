import SwiftUI
import Foundation
import UIKit

@MainActor
final class AppContainer: ObservableObject {
    let session: URLSession
    let authService: AuthService
    let reservationAPI: ReservationAPI
    let reservations = ReservationStore()
    let watchSync = WatchSyncService()
    @Published var isAuthenticated: Bool
    @Published var sessionMessage: String?

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: configuration)
        authService = AuthService(session: session)
        reservationAPI = ReservationAPI(session: session)
        isAuthenticated = false
        sessionMessage = nil
        restoreCookies()
        isAuthenticated = (try? KeychainStore().read("username")) != nil
    }

    func persistCookies() {
        let storage = session.configuration.httpCookieStorage ?? HTTPCookieStorage.shared
        guard let cookies = storage.cookies else { return }
        let values = cookies.map { cookie in
            [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path,
                "expires": cookie.expiresDate?.timeIntervalSince1970 ?? 0
            ] as [String: Any]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let encoded = String(data: data, encoding: .utf8) else { return }
        try? KeychainStore().save(encoded, for: "cookies")
    }

    func expireSession() {
        clearSession()
        sessionMessage = "登录会话已失效，请重新登录"
        isAuthenticated = false
    }

    func logout() {
        clearSession()
        sessionMessage = nil
        isAuthenticated = false
    }

    private func clearSession() {
        try? KeychainStore().delete("username")
        let cookies = session.configuration.httpCookieStorage ?? HTTPCookieStorage.shared
        cookies.cookies?.forEach { cookies.deleteCookie($0) }
        try? KeychainStore().delete("cookies")
    }

    private func restoreCookies() {
        guard let encoded = try? KeychainStore().read("cookies"),
              let data = encoded.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let storage = session.configuration.httpCookieStorage ?? HTTPCookieStorage.shared
        for item in values {
            guard let name = item["name"] as? String,
                  let cookieValue = item["value"] as? String,
                  let domain = item["domain"] as? String,
                  let path = item["path"] as? String else { continue }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: cookieValue, .domain: domain, .path: path
            ]
            if let timestamp = item["expires"] as? Double, timestamp > 0 {
                properties[.expires] = Date(timeIntervalSince1970: timestamp)
            }
            if let cookie = HTTPCookie(properties: properties) {
                storage.setCookie(cookie)
            }
        }
    }
}

struct RootView: View {
    @ObservedObject var container: AppContainer
    @AppStorage("themeMode") private var themeMode = "system"

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
        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

struct LoginView: View {
    @ObservedObject var container: AppContainer
    @State private var username = ""
    @State private var password = ""
    @State private var challenge: AuthChallenge?
    @State private var showingVerification = false
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.blue.opacity(0.12), .white], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "bus.doubledecker").font(.system(size: 48, weight: .semibold)).foregroundStyle(.blue)
                Text("iShuttle").font(.system(size: 34, weight: .bold, design: .rounded))
                Text("新燕园人的出行助手").font(.subheadline).foregroundStyle(.secondary)
                VStack(spacing: 14) {
                    LoginField(icon: "person", title: "账号") { TextField("学号 / 职工号 / 手机号", text: $username).textContentType(.username) }
                    LoginField(icon: "lock", title: "密码") { SecureField("请输入密码", text: $password).textContentType(.password) }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
                Button { Task { await beginLogin() } } label: {
                    HStack { if loading { ProgressView().tint(.white) }; Text(loading ? "登录中…" : "登录") }
                        .frame(maxWidth: .infinity).frame(height: 52)
                }
                .buttonStyle(.borderedProminent).tint(.blue).clipShape(RoundedRectangle(cornerRadius: 14))
                .disabled(loading || username.isEmpty || password.isEmpty)
            }
            .frame(maxWidth: 430)
            .padding(24)
        }
        .sheet(isPresented: $showingVerification) {
            if let challenge { VerificationDialog(challenge: challenge, authService: container.authService, username: username, password: password) { showingVerification = false; container.persistCookies(); container.isAuthenticated = true }.presentationDetents([.medium]).presentationDragIndicator(.visible) }
        }
    }

    private func beginLogin() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let challenge = try await container.authService.prepareLogin(username: username)
            self.challenge = challenge
            if challenge.kind != .none { showingVerification = true; return }
            try await container.authService.login(username: username, password: password)
            try KeychainStore().save(username, for: "username")
            container.persistCookies()
            container.isAuthenticated = true
        } catch { errorMessage = error.localizedDescription }
    }
}

struct VerificationDialog: View {
    let challenge: AuthChallenge
    let authService: AuthService
    let username: String
    let password: String
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var rememberDevice = false
    @State private var isLoading = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 34)).foregroundStyle(.blue)
                Text(challenge.kind == .sms ? "输入验证码" : "输入手机令牌").font(.title2.bold())
                Text("为了保护你的账号，需要完成二次认证。").font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    TextField(challenge.kind == .sms ? "短信 / 邮件验证码" : "手机令牌", text: $code).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    if challenge.kind == .sms { Button("发送") { Task { await sendCode() } } }
                }
                if challenge.canRememberDevice { Toggle("信任此设备", isOn: $rememberDevice) }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                Button { Task { await submit() } } label: { Text("继续登录").frame(maxWidth: .infinity).frame(height: 48) }.buttonStyle(.borderedProminent).disabled(code.isEmpty || isLoading)
            }
            .padding(24)
            .navigationTitle("安全验证").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    private func sendCode() async {
        do { message = try await authService.sendVerificationCode() } catch { errorMessage = error.localizedDescription }
    }

    private func submit() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.login(username: username, password: password, verificationCode: code, rememberDevice: rememberDevice)
            try KeychainStore().save(username, for: "username")
            onSuccess()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct LoginField<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.blue).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                content.font(.body)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
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

struct SettingsView: View {
    @ObservedObject var container: AppContainer
    @AppStorage("themeMode") private var themeMode = "system"
    @State private var showingLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text((try? KeychainStore().read("username")) ?? "北京大学用户")
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

                Section {
                    Button(role: .destructive) {
                        showingLogoutConfirmation = true
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("设置")
            .confirmationDialog("确定要退出当前账号吗？", isPresented: $showingLogoutConfirmation, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    container.logout()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

struct ReservationView: View {
    let store: ReservationStore
    @ObservedObject var container: AppContainer
    @State private var selectedDate = Date()
    @State private var selectedDirection: CommuteDirection = .toChangping
    @State private var locationDirectionApplied = false
    @State private var locationService = LocationDirectionService()
    @State private var locationToast: String?
    @StateObject private var viewModel: ReservationViewModel

    init(store: ReservationStore, container: AppContainer) {
        self.store = store
        self.container = container
        _viewModel = StateObject(wrappedValue: ReservationViewModel(
            api: container.reservationAPI,
            store: store,
            onAuthenticationRequired: { container.expireSession() },
            onReservationsChanged: { values in container.watchSync.sync(values) }
        ))
    }

    private var beijingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    WeekDatePicker(selectedDate: $selectedDate, calendar: beijingCalendar)
                        .onChange(of: selectedDate) { _, newDate in
                            Task { await viewModel.refresh(on: newDate, calendar: beijingCalendar) }
                        }
                let relevantBuses = viewModel.buses.filter { RouteLogic.direction(for: $0.routeName) != nil }
                let grouped = Dictionary(grouping: relevantBuses, by: { RouteLogic.direction(for: $0.routeName) })
                let routeBuses = (grouped[selectedDirection] ?? []).sorted { $0.departure < $1.departure }
                Picker("班车方向", selection: $selectedDirection) {
                    Text("海淀 → 昌平").tag(CommuteDirection.toChangping)
                    Text("昌平 → 海淀").tag(CommuteDirection.toHaidian)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("班车方向")

                if routeBuses.isEmpty {
                    ContentUnavailableView(
                        selectedDateIsToday ? "今天已经没车了" : "当天没有班车",
                        systemImage: "bus"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        if routeBuses.contains(where: { RouteLogic.hasDelayedChangpingArrival($0.routeName) }) {
                            Label("从200号校区出发的班车，到昌平晚约20分钟", systemImage: "clock.badge.exclamationmark")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 4)
                                .padding(.bottom, 8)
                        }
                        ForEach(routeBuses) { bus in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(bus.departure.formatted(date: .omitted, time: .shortened))
                                        .font(.title3.weight(.semibold))
                                    Text(RouteLogic.displayRouteName(bus.routeName))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let reservation = reservation(for: bus) {
                                    Button("取消") { Task { await viewModel.cancel(reservation) } }
                                        .buttonStyle(.bordered)
                                        .tint(.secondary)
                                        .frame(width: 78, height: 36)
                                } else {
                                    Button("预约") { Task { await viewModel.reserve(bus, calendar: beijingCalendar) } }
                                        .buttonStyle(.borderedProminent)
                                        .tint(RouteLogic.hasDelayedChangpingArrival(bus.routeName) ? .orange : .blue)
                                        .frame(width: 78, height: 36)
                                }
                            }
                            .padding(14)
                            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.bottom, 8)
                        }
                    }
                }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("班车预约")
            .overlay { if viewModel.isLoading { ProgressView() } }
            .task {
                locationService.onDirection = { campus, direction in
                    guard !locationDirectionApplied else { return }
                    selectedDirection = direction
                    locationDirectionApplied = true
                    let directionName = direction == .toChangping ? "去昌平" : "去海淀"
                    let message = "已定位到" + campus + "，已设置为" + directionName
                    locationToast = message
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        if locationToast == message {
                            locationToast = nil
                        }
                    }
                }
                locationService.requestDirection()
                await viewModel.refresh(on: selectedDate, calendar: beijingCalendar)
            }
            .refreshable { await viewModel.refresh(on: selectedDate, calendar: beijingCalendar) }
            .alert("操作失败", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) { Button("确定") { viewModel.errorMessage = nil } } message: {
                Text(viewModel.errorMessage ?? "未知错误")
            }
            .overlay(alignment: .top) {
                if let locationToast {
                    Label(locationToast, systemImage: "location.fill")
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
            .animation(.easeInOut(duration: 0.2), value: locationToast)
        }
    }

    private var selectedDateIsToday: Bool {
        beijingCalendar.isDate(selectedDate, inSameDayAs: Date())
    }

    private func reservation(for bus: BusOption) -> Reservation? {
        viewModel.reservations.first {
            $0.routeName == bus.routeName && abs($0.departure.timeIntervalSince(bus.departure)) < 60
        }
    }

}

struct WeekDatePicker: View {
    @Binding var selectedDate: Date
    let calendar: Calendar

    private var dates: [Date] {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let mondayOffset = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: today) else { return [] }
        return (0..<14).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private var selectableRange: ClosedRange<Date> {
        let today = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 6, to: today) ?? today
        return today...end
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    let date = dates[index]
                    Text(calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { column in
                        let date = dates[row * 7 + column]
                        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                        let isSelectable = selectableRange.contains(date)
                        Button {
                            selectedDate = date
                        } label: {
                            Text(calendar.component(.day, from: date), format: .number)
                                .font(.subheadline.weight(isSelected ? .bold : .regular))
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(isSelected ? Color.accentColor : Color.clear, in: Circle())
                                .foregroundStyle(isSelected ? Color.white : (isSelectable ? Color.primary : Color.secondary.opacity(0.35)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!isSelectable)
                        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct MyReservationsView: View {
    let store: ReservationStore
    @ObservedObject var container: AppContainer
    @StateObject private var viewModel: ReservationViewModel
    @State private var selectedReservation: Reservation?

    init(store: ReservationStore, container: AppContainer) {
        self.store = store
        self.container = container
        _viewModel = StateObject(wrappedValue: ReservationViewModel(
            api: container.reservationAPI,
            store: store,
            onAuthenticationRequired: { container.expireSession() },
            onReservationsChanged: { values in container.watchSync.sync(values) }
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
                ReservationQRCodeView(reservation: reservation, api: container.reservationAPI)
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

struct ReservationQRCodeView: View {
    let reservation: Reservation
    let api: ReservationAPI
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
                    payload = try await api.qrCode(for: reservation)
                } catch is CancellationError {
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

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
            let cached = await store.load()
            reservation = cached.filter(\.isVisibleAt).sorted { $0.departure < $1.departure }.first
            print("[QRHome] 本地缓存 reservations=\(cached.count)")
            do {
                let remote = try await container.reservationAPI.currentReservations()
                print("[QRHome] 远端 reservations=\(remote.count)")
                for item in remote {
                    if let old = cached.first(where: { $0.id == item.id }), let code = old.qrCodePayload {
                        print("[QRHome] 使用缓存二维码 id=\(item.id), payloadLength=\(code.count)")
                        await store.upsert(Reservation(
                            id: item.id,
                            hallAppointmentDataID: item.hallAppointmentDataID,
                            routeName: item.routeName,
                            departure: item.departure,
                            qrCodePayload: code
                        ))
                    } else {
                        do {
                            let code = try await container.reservationAPI.qrCode(for: item)
                            print("[QRHome] 获取二维码成功 id=\(item.id), payloadLength=\(code.count)")
                            await store.upsert(Reservation(
                                id: item.id,
                                hallAppointmentDataID: item.hallAppointmentDataID,
                                routeName: item.routeName,
                                departure: item.departure,
                                qrCodePayload: code
                            ))
                        } catch {
                            print("[QRHome] 获取二维码失败 id=\(item.id): \(error.localizedDescription)")
                            throw error
                        }
                    }
                }
                let updated = await store.all()
                reservation = updated.filter(\.isVisibleAt).sorted { $0.departure < $1.departure }.first
                print("[QRHome] 刷新完成，sync reservations=\(updated.count)")
                container.watchSync.sync(updated)
            } catch {
                print("[QRHome] 刷新失败: \(error.localizedDescription)")
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
