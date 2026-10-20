import Foundation
import Observation
import OSLog

let apiLog = Logger(subsystem: "com.inkpi.app", category: "api")
let appLog = Logger(subsystem: "com.inkpi.app", category: "app")

struct APIError: LocalizedError, Sendable {
    var status: Int
    var code: String?
    var message: String
    var payload: JSONValue?

    var errorDescription: String? { message }

    var isAuthError: Bool { status == 401 || code == "invalid_token" }
}

private let errorTextMap: [String: String] = [
    "invalid_credentials": "账号或密码不正确",
    "username_exists": "这个用户名已经被注册",
    "missing_token": "请先登录",
    "invalid_token": "登录已过期，请重新登录",
    "result_not_found": "记录不存在或已删除",
    "invalid_device_key": "设备密钥不匹配",
    "camera_unavailable": "摄像头不可用",
]

/// Same wording as `InkUI.errorText` in the shared web UI.
func errorText(_ error: Error) -> String {
    if let api = error as? APIError {
        if let code = api.code, let text = errorTextMap[code] { return text }
        return api.message
    }
    return error.localizedDescription
}

struct RequestEntry: Identifiable, Codable, Sendable {
    var id = UUID()
    var at: Date
    var method: String
    var url: String
    var status: Int
    var ms: Int
    var client: String
    var request: JSONValue?
    var response: JSONValue?
    var error: String?

    var ok: Bool { status >= 200 && status < 400 }
    var path: String {
        guard let comps = URLComponents(string: url) else { return url }
        return comps.percentEncodedPath + (comps.percentEncodedQuery.map { "?\($0)" } ?? "")
    }
}

/// In-memory request log shared by every client (the 调试 tab shows it).
@MainActor @Observable
final class RequestLog {
    static let shared = RequestLog()
    private(set) var entries: [RequestEntry] = []

    func push(_ entry: RequestEntry) {
        entries.insert(entry, at: 0)
        if entries.count > 200 { entries.removeLast(entries.count - 200) }
    }

    func clear() { entries.removeAll() }
}

/// Small JSON HTTP client mirroring `InkUI.createClient`: base URL, optional
/// bearer token, per-call timeout, `ok:false` payloads treated as errors and
/// every request recorded in `RequestLog`.
@MainActor
struct APIClient {
    var name: String
    var base: () -> String
    var token: () -> String? = { nil }
    var timeout: TimeInterval = 15
    var wifiOnly: () -> Bool = { false }

    func get(_ path: String, timeout: TimeInterval? = nil) async throws -> JSONValue {
        try await request("GET", path, timeout: timeout)
    }

    func post(_ path: String, _ json: JSONValue = .object([:]), timeout: TimeInterval? = nil) async throws -> JSONValue {
        try await request("POST", path, json: json, timeout: timeout)
    }

    func delete(_ path: String) async throws -> JSONValue {
        try await request("DELETE", path)
    }

    func url(_ path: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        var root = base()
        while root.hasSuffix("/") { root.removeLast() }
        return URL(string: root + path)
    }

    func request(_ method: String, _ path: String, json: JSONValue? = nil, timeout: TimeInterval? = nil) async throws -> JSONValue {
        let limit = timeout ?? self.timeout
        guard let url = self.url(path), url.scheme != nil, url.host() != nil else {
            throw APIError(status: 0, message: "地址无效：\(base())\(path)")
        }
        var req = URLRequest(url: url, timeoutInterval: limit)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = token(), !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(json)
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = limit
        config.timeoutIntervalForResource = limit
        config.waitsForConnectivity = false
        // The setup hotspot has no internet; keep those requests on Wi-Fi
        // (the iOS counterpart of Android's bindProcessToNetwork).
        if wifiOnly() { config.allowsCellularAccess = false }
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var entry = RequestEntry(at: Date(), method: method, url: url.absoluteString, status: 0, ms: 0, client: name, request: json)
        let started = Date()
        apiLog.debug("\(name, privacy: .public) \(method, privacy: .public) \(url.absoluteString, privacy: .public)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            entry.ms = Int(Date().timeIntervalSince(started) * 1000)
            let timedOut = (error as? URLError)?.code == .timedOut
            entry.error = timedOut ? "timeout \(Int(limit * 1000))ms" : error.localizedDescription
            RequestLog.shared.push(entry)
            apiLog.error("\(name, privacy: .public) \(method, privacy: .public) \(url.absoluteString, privacy: .public) failed: \(entry.error ?? "", privacy: .public)")
            throw APIError(status: 0, message: timedOut ? "请求超时" : "网络不可用：\(error.localizedDescription)")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        let body: JSONValue = (type.contains("json") ? JSONValue.parse(data) : nil)
            ?? .string(String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>")
        entry.status = status
        entry.ms = Int(Date().timeIntervalSince(started) * 1000)
        entry.response = body
        RequestLog.shared.push(entry)
        apiLog.debug("\(name, privacy: .public) \(method, privacy: .public) \(url.path(), privacy: .public) -> \(status) \(entry.ms)ms")

        if !(200..<300).contains(status) || body["ok"]?.bool == false {
            let code = body["error"]?.string
            let message = body["message"]?.string ?? code ?? "HTTP \(status)"
            throw APIError(status: status, code: code, message: message, payload: body)
        }
        return body
    }
}
