import Foundation
import Network
import Observation
import OSLog
import UIKit

/// Network reachability for the 调试 / 我的 screens (Android shows the active
/// network from ConnectivityManager).
@MainActor @Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var summary = "检测中…"
    private(set) var onWiFi = false
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let wifi = path.usesInterfaceType(.wifi)
            var parts: [String] = []
            if path.status != .satisfied {
                parts.append(path.status == .requiresConnection ? "需要连接" : "离线")
            }
            if wifi { parts.append("Wi-Fi") }
            if path.usesInterfaceType(.cellular) { parts.append("蜂窝") }
            if path.usesInterfaceType(.wiredEthernet) { parts.append("有线") }
            if path.isExpensive { parts.append("计费") }
            if path.isConstrained { parts.append("低数据模式") }
            let text = parts.isEmpty ? "在线" : parts.joined(separator: " · ")
            Task { @MainActor in
                NetworkMonitor.shared.summary = text
                NetworkMonitor.shared.onWiFi = wifi
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.inkpi.app.path"))
    }
}

enum Diagnostics {
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "--"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "--"
    }

    static var buildType: String {
        #if DEBUG
        return "debug"
        #else
        return "release（未签名）"
        #endif
    }

    static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        return mirror.children.reduce(into: "") { result, element in
            if let value = element.value as? Int8, value != 0 { result.append(Character(UnicodeScalar(UInt8(value)))) }
        }
    }

    @MainActor
    static func environment(_ state: AppState) -> [(String, String)] {
        let device = UIDevice.current
        return [
            ("App 版本", "\(appVersion) (\(buildNumber)) \(buildType)"),
            ("iOS", "\(device.systemName) \(device.systemVersion)"),
            ("设备", "\(device.model) \(modelIdentifier)"),
            ("界面", "SwiftUI 原生 · Liquid Glass"),
            ("网络", NetworkMonitor.shared.summary),
            ("云端", state.server),
            ("设备直连", state.device.isEmpty ? "未设置（在「我的」里填写）" : state.device),
            ("热点请求", state.hotspotWifiOnly ? "仅 Wi-Fi" : "系统默认"),
            ("登录", state.userName ?? "未登录"),
        ]
    }

    /// The app's own unified-log lines (the iOS stand-in for Android logcat).
    static func recentLogs(limit: Int = 300) async -> String {
        await Task.detached(priority: .userInitiated) { () -> String in
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let since = store.position(date: Date().addingTimeInterval(-6 * 3600))
                let lines = try store.getEntries(at: since)
                    .compactMap { $0 as? OSLogEntryLog }
                    .filter { $0.subsystem == "com.inkpi.app" }
                    .suffix(limit)
                    .map { "\($0.date.formatted(date: .omitted, time: .standard)) [\($0.category)] \($0.composedMessage)" }
                return lines.isEmpty ? "还没有日志" : lines.joined(separator: "\n")
            } catch {
                return "读取日志失败：\(error.localizedDescription)"
            }
        }.value
    }
}
