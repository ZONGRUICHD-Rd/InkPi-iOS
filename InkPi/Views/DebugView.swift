import SwiftUI
import UIKit
import WebKit

/// 调试: every debug hook the Android build has, mapped to iOS.
struct DebugView: View {
    @Environment(AppState.self) private var state

    private struct Check: Identifiable {
        var title: String
        var target: String
        var path: String
        var method = "GET"
        var id: String { title }
    }

    private let checks: [Check] = [
        Check(title: "云端健康", target: "cloud", path: "/api/health"),
        Check(title: "云端调试信息", target: "cloud", path: "/api/debug/info"),
        Check(title: "云端请求记录", target: "cloud", path: "/api/debug/requests?limit=30"),
        Check(title: "云端回显", target: "cloud", path: "/api/debug/echo"),
        Check(title: "设备状态", target: "device", path: "/api/device/status"),
        Check(title: "设备调试信息", target: "device", path: "/api/debug/info"),
        Check(title: "设备日志", target: "device", path: "/api/debug/logs?lines=80"),
        Check(title: "网络服务事件", target: "netd", path: "/api/net/debug"),
        Check(title: "热点状态", target: "setup", path: "/api/net/status"),
        Check(title: "设备补同步", target: "device", path: "/api/debug/cloud-sync", method: "POST"),
    ]

    private let targets: [(String, String)] = [("cloud", "云端"), ("device", "设备"), ("netd", "网络服务"), ("setup", "热点"), ("custom", "完整 URL")]

    @State private var checkOutput: String?
    @State private var checkBusy: String?
    @State private var consoleTarget = "cloud"
    @State private var consoleMethod = "GET"
    @State private var consolePath = "/api/health"
    @State private var consoleBody = ""
    @State private var consoleOutput: String?
    @State private var consoleBusy = false
    @State private var nativeOutput: String?
    @State private var showingWeb = false
    @State private var confirmingWipe = false

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        Banner(.warn, "开发版：所有调试接口均已开启。日志可在 Mac 的 Xcode 控制台或「控制台」App 中按 com.inkpi.app 过滤查看。")
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }

                    Section("环境") {
                        ForEach(Array(Diagnostics.environment(state).enumerated()), id: \.offset) { _, item in
                            LabeledContent(item.0) {
                                Text(item.1).multilineTextAlignment(.trailing).textSelection(.enabled)
                            }
                        }
                    }

                    Section("快速检查") {
                        GlassEffectContainer(spacing: 8) {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                                ForEach(checks) { check in
                                    Button {
                                        Task { await run(check) }
                                    } label: {
                                        HStack(spacing: 6) {
                                            if checkBusy == check.id { ProgressView().controlSize(.mini) }
                                            Text(check.title).lineLimit(1).minimumScaleFactor(0.8)
                                        }
                                        .font(.footnote.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.glass)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                        if let checkOutput {
                            CodeBlock(text: checkOutput)
                        }
                    }

                    Section("API 控制台") {
                        Picker("目标", selection: $consoleTarget) {
                            ForEach(Array(targets.enumerated()), id: \.offset) { _, t in Text(t.1).tag(t.0) }
                        }
                        Picker("方法", selection: $consoleMethod) {
                            ForEach(["GET", "POST", "DELETE"], id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        TextField("/api/health", text: $consolePath)
                            .font(.callout.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        ZStack(alignment: .topLeading) {
                            if consoleBody.isEmpty {
                                Text("JSON 请求体，例如 {\"limit\": 5}")
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                            }
                            TextEditor(text: $consoleBody)
                                .font(.callout.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .frame(minHeight: 80)
                                .scrollContentBackground(.hidden)
                        }
                        Button {
                            Task { await send() }
                        } label: {
                            HStack {
                                if consoleBusy { ProgressView().tint(.white) }
                                Text("发送")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(consoleBusy)
                        if let consoleOutput {
                            CodeBlock(text: consoleOutput).id("console-output")
                        }
                    }

                    Section {
                        let entries = RequestLog.shared.entries.prefix(60)
                        if entries.isEmpty {
                            Text("还没有请求").foregroundStyle(.secondary)
                        }
                        ForEach(entries) { entry in
                            Button {
                                consoleOutput = entry.prettyJSON
                                withAnimation { proxy.scrollTo("console-output", anchor: .center) }
                            } label: {
                                LogRow(entry: entry)
                            }
                        }
                    } header: {
                        Text("请求记录（本机）")
                    } footer: {
                        HStack(spacing: 16) {
                            Button("复制全部记录") {
                                copy(RequestLog.shared.entries.prettyJSON)
                            }
                            Button("清空", role: .destructive) {
                                RequestLog.shared.clear()
                            }
                        }
                        .font(.footnote.weight(.medium))
                        .padding(.top, 4)
                    }

                    Section {
                        TextField("http://192.168.0.47:5000/ui/device/", text: $state.devWebURL)
                            .font(.callout.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Button {
                            if URL(string: state.devWebURL)?.scheme != nil { showingWeb = true }
                            else { state.show("请先填写完整的网页地址", error: true) }
                        } label: {
                            Label("在应用内打开网页界面", systemImage: "safari")
                        }
                        Toggle(isOn: $state.hotspotWifiOnly) {
                            Label("热点请求仅走 Wi-Fi", systemImage: "wifi.router")
                        }
                        Button {
                            state.reloadID = UUID()
                            state.show("界面已重载")
                        } label: {
                            Label("重载界面", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            nativeOutput = "读取中…"
                            Task { nativeOutput = await Diagnostics.recentLogs() }
                        } label: {
                            Label("查看应用日志", systemImage: "doc.text.magnifyingglass")
                        }
                        ShareLink(item: diagnosticsText()) {
                            Label("分享诊断信息", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                        } label: {
                            Label("打开系统设置（本地网络权限）", systemImage: "gear")
                        }
                        Button(role: .destructive) {
                            confirmingWipe = true
                        } label: {
                            Label("清除本地数据", systemImage: "trash")
                        }
                        if let nativeOutput {
                            CodeBlock(text: nativeOutput)
                        }
                    } header: {
                        Text("原生")
                    } footer: {
                        Text("网页界面地址可填设备屏幕界面（/ui/device/）或配网页，用于对照调试。")
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("调试")
            .confirmationDialog("清除登录状态和全部本地设置？", isPresented: $confirmingWipe, titleVisibility: .visible) {
                Button("清除", role: .destructive) { Task { await state.wipe() } }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showingWeb) {
                DevWebSheet(url: URL(string: state.devWebURL))
            }
        }
    }

    private func run(_ check: Check) async {
        if check.target == "device" && state.device.isEmpty {
            checkOutput = "未设置设备直连地址，请在「我的」里填写，例如 http://192.168.0.47:5000"
            return
        }
        checkBusy = check.id
        checkOutput = "请求中…"
        defer { checkBusy = nil }
        do {
            let data = try await state.client(check.target).request(check.method, check.path, json: check.method == "POST" ? .object([:]) : nil)
            checkOutput = data.pretty
        } catch {
            checkOutput = "失败：\(errorText(error))\n\((error as? APIError)?.payload?.pretty ?? "")"
        }
    }

    private func send() async {
        let path = consolePath.trimmingCharacters(in: .whitespacesAndNewlines)
        var json: JSONValue?
        let raw = consoleBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            guard let parsed = JSONValue.parse(raw) else {
                consoleOutput = "请求体不是合法 JSON"
                return
            }
            json = parsed
        }
        consoleBusy = true
        consoleOutput = "请求中…"
        defer { consoleBusy = false }
        do {
            let data = try await state.client(consoleTarget).request(consoleMethod, path, json: json)
            consoleOutput = data.pretty
        } catch {
            let api = error as? APIError
            consoleOutput = "HTTP \(api?.status ?? 0): \(errorText(error))\n\(api?.payload?.pretty ?? "")"
        }
    }

    private func diagnosticsText() -> String {
        let env = Dictionary(Diagnostics.environment(state), uniquingKeysWith: { a, _ in a })
        struct Report: Encodable {
            var env: [String: String]
            var requests: [RequestEntry]
        }
        return Report(env: env, requests: Array(RequestLog.shared.entries.prefix(50))).prettyJSON
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        state.show("已复制")
    }
}

private struct LogRow: View {
    var entry: RequestEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(entry.status == 0 ? "ERR" : "\(entry.status)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(entry.ok ? Color.inkGood : Color.inkBad)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background((entry.ok ? Color.inkGood : Color.inkBad).opacity(0.14), in: .capsule)
                Text(entry.method).font(.caption.weight(.semibold))
                Text(entry.path).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
            }
            .foregroundStyle(.primary)
            Text("\(entry.ms)ms · \(entry.client) · \(entry.at.formatted(date: .omitted, time: .standard))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let error = entry.error {
                Text(error).font(.caption2).foregroundStyle(Color.inkBad)
            }
        }
    }
}

/// In-app browser for the shared web UI (the counterpart of the Android
/// build's "开发界面地址").
private struct DevWebSheet: View {
    @Environment(\.dismiss) private var dismiss
    var url: URL?
    @State private var page = WebPage(configuration: WebPage.Configuration())

    var body: some View {
        NavigationStack {
            WebView(page)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(page.title.isEmpty ? (url?.host() ?? "网页") : page.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            _ = page.reload(fromOrigin: false)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("重新加载")
                    }
                }
                .overlay(alignment: .top) {
                    if page.isLoading {
                        ProgressView(value: page.estimatedProgress).progressViewStyle(.linear)
                    }
                }
                .onAppear {
                    if let url { _ = page.load(URLRequest(url: url)) }
                }
        }
    }
}
