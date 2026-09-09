import Foundation

final class AuthService {
    private let session: URLSession
    private let iaaa = "https://iaaa.pku.edu.cn"
    private let wproc = "https://wproc.pku.edu.cn"
    private let wprocRedirectURL = "https://wproc.pku.edu.cn/site/login/cas-login?redirect_url=https%3A%2F%2Fwproc.pku.edu.cn%2Fv2%2Fsite%2Findex"
    private var publicKey: String?
    private var preparedUser: String?
    private(set) var challenge = AuthChallenge(kind: .none, emailVerification: false, canRememberDevice: false)

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        self.session = session ?? URLSession(configuration: configuration)
    }

    func prepareLogin(username: String) async throws -> AuthChallenge {
        preparedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let user = preparedUser, !user.isEmpty else {
            throw APIError.invalidResponse("请输入账号")
        }
        var oauthComponents = URLComponents(string: iaaa + "/iaaa/oauth.jsp")!
        oauthComponents.queryItems = [
            URLQueryItem(name: "appID", value: "wproc"),
            URLQueryItem(name: "appName", value: "办事大厅预约版"),
            URLQueryItem(name: "redirectUrl", value: wprocRedirectURL)
        ]
        let oauth = oauthComponents.url!
        _ = try await session.data(from: oauth)
        let captcha = try await get("/iaaa/isShowCode.do")
        if Self.asBool(captcha["success"]) {
            throw APIError.invalidResponse("登录需要图形验证码")
        }
        let key = try await get("/iaaa/getPublicKey.do")
        guard let pem = key["key"] as? String else {
            throw APIError.invalidResponse("无法获取登录公钥")
        }
        publicKey = pem
        var components = URLComponents(string: iaaa + "/iaaa/isMobileAuthen.do")!
        components.queryItems = [URLQueryItem(name: "userName", value: user), URLQueryItem(name: "appId", value: "wproc"), URLQueryItem(name: "_rand", value: UUID().uuidString)]
        let capability = try await getURL(components.url!)
        challenge = Self.parseChallenge(capability)
        return challenge
    }

    func sendVerificationCode() async throws -> String {
        guard let user = preparedUser else {
            throw APIError.invalidResponse("登录会话已失效")
        }
        var components = URLComponents(string: iaaa + "/iaaa/sendSMSCode.do")!
        components.queryItems = [
            URLQueryItem(name: "userName", value: user),
            URLQueryItem(name: "appId", value: "wproc"),
            URLQueryItem(name: "_rand", value: UUID().uuidString)
        ]
        let response = try await getURL(components.url!)
        guard Self.asBool(response["success"]) else {
            throw APIError.invalidResponse("验证码发送失败")
        }
        let target = response["mobileMask"] as? String ?? "绑定设备"
        return "验证码已发送至 \(target)"
    }

    func login(
        username: String,
        password: String,
        verificationCode: String? = nil,
        rememberDevice: Bool = false
    ) async throws {
        let current: AuthChallenge
        if preparedUser == username, publicKey != nil {
            current = challenge
        } else {
            current = try await prepareLogin(username: username)
        }
        if current.kind != .none && (verificationCode?.isEmpty ?? true) {
            let message = current.kind == .sms ? "请输入短信或邮件验证码" : "请输入手机令牌"
            throw APIError.invalidResponse(message)
        }
        guard let pem = publicKey else {
            throw APIError.invalidResponse("登录公钥已失效")
        }
        let encrypted = try RSA.encryptPKCS1(password: password, pem: pem)
        var request = URLRequest(url: URL(string: iaaa + "/iaaa/oauthlogin.do")!)
        request.httpMethod = "POST"
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) " +
                "AppleWebKit/605.1.15 Version/26.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let code = verificationCode ?? ""
        request.httpBody = form([
            "appid": "wproc",
            "userName": username,
            "password": encrypted,
            "randCode": "",
            "smsCode": current.kind == .sms ? code : "",
            "otpCode": current.kind == .otp ? code : "",
            "remTrustChk": String(rememberDevice),
            "redirUrl": wprocRedirectURL
        ])
        let (data, response) = try await session.data(for: request)
        try validate(response)
        let result = try object(data)
        guard Self.asBool(result["success"]),
              let token = result["token"] as? String,
              !token.isEmpty else {
            throw APIError.invalidResponse(Self.authenticationMessage(from: result))
        }
        var cas = URLComponents(string: wproc + "/site/login/cas-login")!
        cas.queryItems = [
            URLQueryItem(name: "redirect_url", value: wproc + "/v2/site/index"),
            URLQueryItem(name: "_rand", value: UUID().uuidString),
            URLQueryItem(name: "token", value: token)
        ]
        _ = try await session.data(from: cas.url!)
        try await validateWProcSession()
    }

    private func validateWProcSession() async throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        var components = URLComponents(string: wproc + "/site/reservation/list-page")!
        components.queryItems = [
            URLQueryItem(name: "hall_id", value: "1"),
            URLQueryItem(name: "time", value: formatter.string(from: Date())),
            URLQueryItem(name: "p", value: "1"),
            URLQueryItem(name: "page_size", value: "0")
        ]
        let (data, response) = try await session.data(from: components.url!)
        _ = try WProcResponse.decode(data, response: response)
    }

    private func get(_ path: String) async throws -> [String: Any] {
        try await getURL(URL(string: iaaa + path)!)
    }

    private func getURL(_ url: URL) async throws -> [String: Any] {
        let (data, response) = try await session.data(from: url)
        try validate(response)
        return try object(data)
    }

    private func validate(_ response: URLResponse) throws {
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.invalidResponse("服务器请求失败")
        }
    }

    private func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse("服务器返回了无效数据")
        }
        return value
    }

    private func form(_ values: [String: String]) -> Data? {
        let body = values.map { key, value in
            "\(formEncode(key))=\(formEncode(value))"
        }.joined(separator: "&")
        return body.data(using: .utf8)
    }

    private func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func parseChallenge(_ value: [String: Any]) -> AuthChallenge {
        guard Self.asBool(value["success"]),
              Self.asBool(value["isMobileAuthen"]) else {
            return AuthChallenge(kind: .none, emailVerification: false, canRememberDevice: false)
        }
        let mode = (value["authenMode"] as? String ?? "").uppercased()
        let kind: AuthChallenge.Kind
        switch mode {
        case "SMS":
            kind = .sms
        case "OTP":
            kind = .otp
        default:
            kind = .none
        }
        return AuthChallenge(
            kind: kind,
            emailVerification: Self.asBool(value["emailSuitable"]),
            canRememberDevice: Self.asBool(value["isUnuAuth"])
        )
    }

    private static func asBool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            return value.lowercased() == "true" || value == "1"
        }
        return false
    }

    private static func authenticationMessage(from response: [String: Any]) -> String {
        if let errors = response["errors"] as? [String: Any] {
            let code = errors["code"] as? String
            let message = errors["msg"] as? String
            if let code, let message, !message.isEmpty {
                let friendly: String
                switch code {
                case "E01": friendly = "账号或密码错误"
                case "E03": friendly = "登录需要图形验证码，请先在 IAAA 网页完成一次登录后重试"
                case "E04": friendly = "短信或邮件验证码错误或已过期"
                case "E05": friendly = "手机令牌错误或已过期"
                case "E07": friendly = "账号校验失败，请检查账号后重试"
                default: friendly = "登录失败（\(code)）"
                }
                return "\(friendly)（\(message)）"
            }
            if let message, !message.isEmpty {
                return message
            }
        }
        if let message = response["message"] as? String, !message.isEmpty {
            return message
        }
        return "账号或密码错误，或者验证码已失效"
    }

}
