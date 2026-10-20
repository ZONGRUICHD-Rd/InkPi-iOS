import Foundation
import Observation
import SwiftUI
import WebKit

let defaultServer = "http://163.192.62.239:23334"
let setupBase = "http://10.42.0.1"

enum AppTab: Hashable {
    case history, setup, debug, me
}

enum ThemeMode: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: "自动"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var isError: Bool
}

/// App-wide state. Keys match the Android app's localStorage keys
/// (`inkpi.server`, `inkpi.device`, `inkpi.token`, `inkpi.user`, `inkpi.theme`).
@MainActor @Observable
final class AppState {
    private let defaults = UserDefaults.standard

    var server: String { didSet { defaults.set(server, forKey: "inkpi.server") } }
    var device: String { didSet { defaults.set(device, forKey: "inkpi.device") } }
    var token: String { didSet { defaults.set(token, forKey: "inkpi.token") } }
    var user: JSONValue? {
        didSet {
            if let user, let data = try? JSONEncoder().encode(user) { defaults.set(data, forKey: "inkpi.user") }
            else { defaults.removeObject(forKey: "inkpi.user") }
        }
    }
    var theme: ThemeMode { didSet { defaults.set(theme.rawValue, forKey: "inkpi.theme") } }
    var devWebURL: String { didSet { defaults.set(devWebURL, forKey: "inkpi.devUi") } }
    var hotspotWifiOnly: Bool { didSet { defaults.set(hotspotWifiOnly, forKey: "inkpi.hotspotWifiOnly") } }

    /// Login screen vs. tabs. Like the Android router, 配网 / 调试 / 我的 work
    /// without signing in; 记录 sends you to the login screen.
    var showingLogin: Bool
    var tab: AppTab = .history
    var historyPath: [Int] = []
    var historyVersion = 0
    var reloadID = UUID()
    var toast: Toast?

    init() {
        server = defaults.string(forKey: "inkpi.server") ?? defaultServer
        device = defaults.string(forKey: "inkpi.device") ?? ""
        token = defaults.string(forKey: "inkpi.token") ?? ""
        user = defaults.data(forKey: "inkpi.user").flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        theme = ThemeMode(rawValue: defaults.string(forKey: "inkpi.theme") ?? "") ?? .auto
        devWebURL = defaults.string(forKey: "inkpi.devUi") ?? ""
        hotspotWifiOnly = defaults.object(forKey: "inkpi.hotspotWifiOnly") as? Bool ?? true
        showingLogin = (defaults.string(forKey: "inkpi.token") ?? "").isEmpty
    }

    var isAuthed: Bool { !token.isEmpty }
    var userName: String? { user?["username"]?.string }
    var displayName: String? {
        guard let user else { return nil }
        if let name = user["display_name"]?.string, !name.isEmpty { return name }
        return user["username"]?.string
    }

    // MARK: clients

    var cloud: APIClient {
        APIClient(name: "cloud", base: { [unowned self] in server }, token: { [unowned self] in token }, timeout: 15)
    }

    var deviceClient: APIClient {
        APIClient(name: "device", base: { [unowned self] in device }, timeout: 10)
    }

    func client(_ target: String) -> APIClient {
        switch target {
        case "cloud": return cloud
        case "device": return deviceClient
        case "netd":
            let base = device.isEmpty ? setupBase : device.replacingOccurrences(of: #":\d+$"#, with: "", options: .regularExpression)
            return APIClient(name: "netd", base: { base }, timeout: 15)
        case "setup": return setupClient
        default: return APIClient(name: "custom", base: { "" }, timeout: 15)
        }
    }

    var setupClient: APIClient {
        APIClient(name: "netd", base: { setupBase }, timeout: 12, wifiOnly: { [unowned self] in hotspotWifiOnly })
    }

    func imageURL(_ id: Int, _ kind: String) -> URL? {
        var root = server
        while root.hasSuffix("/") { root.removeLast() }
        let encoded = self.token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return URL(string: "\(root)/api/results/\(id)/image/\(kind)?token=\(encoded)")
    }

    // MARK: actions

    func show(_ message: String, error: Bool = false) {
        toast = Toast(message: message, isError: error)
    }

    func setServer(_ value: String) {
        var v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while v.hasSuffix("/") { v.removeLast() }
        server = v.isEmpty ? defaultServer : v
    }

    func setDevice(_ value: String) {
        var v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while v.hasSuffix("/") { v.removeLast() }
        device = v
    }

    func signedIn(token: String, user: JSONValue?) {
        self.token = token
        self.user = user
        historyPath = []
        historyVersion += 1
        tab = .history
        showingLogin = false
    }

    func signOut() {
        token = ""
        user = nil
        historyPath = []
        tab = .history
        showingLogin = true
    }

    /// Returns true when the error means the session is gone (Android `handleAuthError`).
    @discardableResult
    func handleAuthError(_ error: Error) -> Bool {
        guard let api = error as? APIError, api.isAuthError else { return false }
        token = ""
        show("登录已过期，请重新登录", error: true)
        showingLogin = true
        return true
    }

    func open(_ tab: AppTab) {
        if tab == .history && !isAuthed {
            showingLogin = true
            return
        }
        self.tab = tab
        showingLogin = false
    }

    func checkServer() async {
        do {
            _ = try await cloud.get("/api/health", timeout: 6)
            show("服务器可用")
        } catch {
            show("服务器不可用：\(errorText(error))", error: true)
        }
    }

    func checkDevice() async {
        guard !device.isEmpty else { return }
        do {
            let s = try await deviceClient.get("/api/device/status", timeout: 6)
            let app = s["app"]
            let label = [app?["name"]?.string, app?["version"]?.string].compactMap { $0 }.joined(separator: " ")
            show("已连接设备 \(label)")
        } catch {
            show("设备不可达：\(errorText(error))", error: true)
        }
    }

    /// 清除本地数据: settings, login, HTTP caches and web view storage.
    func wipe() async {
        if let id = Bundle.main.bundleIdentifier { defaults.removePersistentDomain(forName: id) }
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        RequestLog.shared.clear()
        server = defaultServer
        device = ""
        token = ""
        user = nil
        theme = .auto
        devWebURL = ""
        hotspotWifiOnly = true
        historyPath = []
        tab = .history
        showingLogin = true
        reloadID = UUID()
    }
}
