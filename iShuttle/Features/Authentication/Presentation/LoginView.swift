import SwiftUI
import Foundation
import UIKit
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
            if let challenge { VerificationDialog(challenge: challenge, authService: container.authService, username: username, password: password) { showingVerification = false; container.completeAuthentication(username: username) }.presentationDetents([.medium]).presentationDragIndicator(.visible) }
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
            container.completeAuthentication(username: username)
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

