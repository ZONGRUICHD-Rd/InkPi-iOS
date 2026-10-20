import Observation
import SwiftUI
import UIKit

/// 配网: step 1 joins the InkPi hotspot in Settings, step 2 talks to inkpi-netd
/// at http://10.42.0.1 (same API as ui/setup/setup.js).
struct SetupView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL
    @State private var model: ProvisioningModel?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("InkPi 没有网络时会自动开启热点（也可以在 InkPi 的「设置」里点「进入配网模式」）。热点名称和密码显示在 InkPi 屏幕上。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        GlassEffectContainer(spacing: 10) {
                            HStack(spacing: 10) {
                                Button {
                                    openWiFiSettings()
                                } label: {
                                    Label("打开 Wi-Fi 设置", systemImage: "gear")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glass)
                                Button {
                                    model?.stop()
                                    let flow = ProvisioningModel(client: state.setupClient)
                                    withAnimation { model = flow }
                                    Task { await flow.start() }
                                } label: {
                                    Text("我已连上热点").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glassProminent)
                            }
                            .controlSize(.large)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("第 1 步：连接 InkPi 热点")
                } footer: {
                    Text("iPhone 在这个热点下显示「无互联网连接」是正常的，保持连接即可。")
                }

                if let model {
                    ProvisioningFlow(model: model)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设备配网")
            .sheet(item: Binding(get: { model?.form }, set: { model?.form = $0 })) { target in
                if let model {
                    NetworkForm(target: target, model: model)
                        .presentationDetents([.medium, .large])
                }
            }
        }
    }

    private func openWiFiSettings() {
        // iOS has no public deep link to the Wi-Fi page; try the Settings
        // URL first and fall back to the app's own settings page.
        let fallback = URL(string: UIApplication.openSettingsURLString)!
        if let url = URL(string: "App-Prefs:WIFI") {
            UIApplication.shared.open(url) { ok in
                if !ok { UIApplication.shared.open(fallback) }
            }
        } else {
            openURL(fallback)
        }
        state.show("请在系统设置里连接 InkPi 热点")
    }
}

struct WiFiNetwork: Identifiable, Hashable {
    var ssid: String
    var signal: Int
    var secure: Bool
    var inUse: Bool
    var id: String { ssid }

    init(_ json: JSONValue) {
        ssid = json["ssid"]?.string ?? ""
        signal = json["signal"]?.int ?? 0
        secure = json["secure"]?.bool ?? true
        inUse = json["in_use"]?.bool ?? false
    }
}

struct FormTarget: Identifiable {
    var network: WiFiNetwork?
    var id: String { network?.ssid ?? "<manual>" }
    var manual: Bool { network == nil }
}

enum ProvisioningPhase: Equatable {
    case pick
    case connecting(String)
    case ok(String)
    case failed(String)
}

@MainActor @Observable
final class ProvisioningModel {
    var status: JSONValue?
    var statusLoaded = false
    var networks: [WiFiNetwork] = []
    var scanning = false
    var scanError: String?
    var phase: ProvisioningPhase = .pick
    var form: FormTarget?
    @ObservationIgnored private let client: APIClient
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(client: APIClient) {
        self.client = client
    }

    func start() async {
        statusLoaded = false
        if await loadStatus() != nil { await loadNetworks(rescan: false) }
    }

    @discardableResult
    func loadStatus() async -> JSONValue? {
        status = try? await client.get("/api/net/status", timeout: 6)
        statusLoaded = true
        return status
    }

    func loadNetworks(rescan: Bool) async {
        scanning = true
        defer { scanning = false }
        do {
            let data = try await client.get("/api/net/scan?rescan=\(rescan ? 1 : 0)", timeout: 30)
            networks = (data["networks"]?.array ?? []).map(WiFiNetwork.init).filter { !$0.ssid.isEmpty }
            scanError = nil
        } catch {
            scanError = errorText(error)
        }
    }

    func connect(ssid: String, password: String, hidden: Bool) async throws {
        _ = try await client.post("/api/net/connect", .object([
            "ssid": .string(ssid),
            "password": .string(password),
            "hidden": .bool(hidden),
        ]))
        form = nil
        withAnimation { phase = .connecting(ssid) }
        poll(ssid)
    }

    func retry() {
        withAnimation { phase = .pick }
        Task { await loadNetworks(rescan: false) }
    }

    func stop() {
        pollTask?.cancel()
    }

    /// Poll every 3 s until the daemon reports the attempt's outcome
    /// (gives up after 40 unreachable polls, like the web flow).
    private func poll(_ ssid: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var misses = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                guard let s = await self.loadStatus() else {
                    misses += 1
                    if misses > 40 { return }
                    continue
                }
                if s["mode"]?.string == "connecting" { continue }
                let attempt = s["last_attempt"]
                guard attempt?["ssid"]?.string == ssid else { continue }
                if attempt?["ok"]?.bool == true {
                    withAnimation { self.phase = .ok(ssid) }
                    return
                }
                if attempt?["ok"]?.bool == false {
                    withAnimation { self.phase = .failed(ssid) }
                    return
                }
            }
        }
    }
}

struct ProvisioningFlow: View {
    var model: ProvisioningModel

    var body: some View {
        Section {
            statusView
        } header: {
            Text("第 2 步：选择家里的 Wi-Fi")
        }

        switch model.phase {
        case .pick:
            Section {
                if model.scanning {
                    HStack { Spacer(); ProgressView("正在扫描…"); Spacer() }
                } else if let scanError = model.scanError {
                    Text(scanError).foregroundStyle(.secondary)
                } else if model.networks.isEmpty && model.statusLoaded && model.status != nil {
                    Text("没有扫描到网络，可以手动输入网络名称。").foregroundStyle(.secondary)
                } else {
                    ForEach(model.networks) { network in
                        Button {
                            model.form = FormTarget(network: network)
                        } label: {
                            NetworkRow(network: network)
                        }
                    }
                }
                Button {
                    model.form = FormTarget(network: nil)
                } label: {
                    Label("手动输入网络名称", systemImage: "plus")
                }
            } header: {
                HStack {
                    Text("选择 Wi-Fi")
                    Spacer()
                    Button {
                        Task { await model.loadNetworks(rescan: true) }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise").labelStyle(.titleAndIcon)
                    }
                    .font(.footnote)
                    .disabled(model.scanning)
                }
            }

        case .connecting(let ssid):
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在连接 \(ssid)…").font(.headline)
                }
                Text("InkPi 会关闭热点去连接这个网络，手机会和热点断开，这是正常的。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Label("成功：InkPi 屏幕右上角会显示网络名称。", systemImage: "checkmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
                Label("失败：大约 1 分钟内热点会重新出现，重新连上热点后回到这个页面再试。", systemImage: "arrow.uturn.backward.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

        case .ok(let ssid):
            Section {
                Banner(.ok, Text("InkPi 已连接 **\(ssid)**"))
                Text("配网完成，可以关闭这个页面。").font(.subheadline).foregroundStyle(.secondary)
            }

        case .failed(let ssid):
            Section {
                Banner(.err, Text("连接 **\(ssid)** 失败：\(model.status?["last_attempt"]?["error"]?.string ?? "请检查密码")"))
                Button("重新选择网络") { model.retry() }
                    .buttonStyle(.glassProminent)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if !model.statusLoaded {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在连接 InkPi…").font(.subheadline).foregroundStyle(.secondary)
            }
        } else if let s = model.status {
            HStack(spacing: 12) {
                BrandMark(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("给 InkPi 连上 Wi-Fi").font(.headline)
                    Text("设备热点 \(s["ap"]?["ssid"]?.string ?? "--") · \(modeText(s["mode"]?.string))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let attempt = s["last_attempt"], attempt["ok"]?.bool == false {
                Banner(.err, Text("上次连接 **\(attempt["ssid"]?.string ?? "")** 失败：\(attempt["error"]?.string ?? "未知原因")"))
            } else if s["mode"]?.string == "station", let ssid = s["wifi"]?["ssid"]?.string {
                Banner(.ok, Text("InkPi 已连接 **\(ssid)**\(s["internet"]?.bool == true ? "，可以访问互联网" : "，但暂时访问不到互联网")"))
            }
        } else {
            Banner(.err, "连接不到 InkPi。请确认手机已连接 InkPi 开头的热点，并允许 InkPi 访问本地网络。")
            Button("重试") { Task { await model.start() } }
        }
    }

    private func modeText(_ mode: String?) -> String {
        switch mode {
        case "ap": "配网模式"
        case "connecting": "正在连接"
        default: "已联网"
        }
    }
}

private struct NetworkRow: View {
    var network: WiFiNetwork

    var body: some View {
        HStack(spacing: 12) {
            SignalBars(signal: network.signal)
            Text(network.ssid).foregroundStyle(.primary).lineLimit(1)
            Spacer()
            if network.inUse {
                Text("当前").font(.caption.weight(.semibold)).foregroundStyle(Color.inkGood)
            }
            if network.secure {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("开放").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(network.ssid)，信号 \(network.signal)\(network.secure ? "，加密" : "，开放")\(network.inUse ? "，当前" : "")")
    }
}

/// Password sheet for one network, or manual SSID entry.
private struct NetworkForm: View {
    @Environment(\.dismiss) private var dismiss

    var target: FormTarget
    var model: ProvisioningModel

    private enum Field: Hashable { case ssid, password }

    @State private var ssid = ""
    @State private var password = ""
    @State private var reveal = false
    @State private var hidden = false
    @State private var error = ""
    @State private var busy = false
    @FocusState private var focus: Field?

    private var needsPassword: Bool { target.manual || (target.network?.secure ?? true) }

    var body: some View {
        NavigationStack {
            Form {
                if target.manual {
                    Section("网络名称（SSID）") {
                        TextField("例如 MyHome", text: $ssid)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .ssid)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                    }
                }
                if needsPassword {
                    Section {
                        HStack {
                            Group {
                                if reveal {
                                    TextField("至少 8 位", text: $password)
                                } else {
                                    SecureField("至少 8 位", text: $password)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .password)
                            .submitLabel(.join)
                            .onSubmit { Task { await connect() } }
                            Button(reveal ? "隐藏" : "显示") { reveal.toggle() }
                                .buttonStyle(.borderless)
                        }
                    } header: {
                        Text("密码")
                    } footer: {
                        if !error.isEmpty { Text(error).foregroundStyle(Color.inkBad) }
                    }
                } else {
                    Section {
                        Text("这是开放网络，不需要密码。").foregroundStyle(.secondary)
                    } footer: {
                        if !error.isEmpty { Text(error).foregroundStyle(Color.inkBad) }
                    }
                }
                if target.manual {
                    Section {
                        Toggle("这是隐藏网络", isOn: $hidden)
                    }
                }
            }
            .navigationTitle(target.manual ? "手动添加网络" : (target.network?.ssid ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("取消")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        Task { await connect() }
                    } label: {
                        if busy { ProgressView() } else { Text("连接") }
                    }
                    .disabled(busy)
                }
            }
            .onAppear { focus = target.manual ? .ssid : (needsPassword ? .password : nil) }
        }
    }

    private func connect() async {
        let name = target.manual ? ssid.trimmingCharacters(in: .whitespaces) : (target.network?.ssid ?? "")
        guard !name.isEmpty else { error = "请输入网络名称"; return }
        if needsPassword && !password.isEmpty && password.count < 8 { error = "Wi-Fi 密码至少 8 位"; return }
        if needsPassword && !target.manual && password.isEmpty { error = "请输入密码"; return }
        busy = true
        defer { busy = false }
        do {
            try await model.connect(ssid: name, password: password, hidden: target.manual && hidden)
        } catch {
            self.error = errorText(error)
        }
    }
}
