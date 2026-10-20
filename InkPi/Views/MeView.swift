import SwiftUI

struct MeView: View {
    @Environment(AppState.self) private var state

    private enum Editing: Identifiable {
        case server, device
        var id: Self { self }
    }

    @State private var editing: Editing?
    @State private var draft = ""
    @State private var confirmingLogout = false

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        BrandMark(text: String((state.displayName ?? "墨").prefix(1)), size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.displayName ?? "未登录").font(.headline)
                            Text(state.userName.map { "@\($0)" } ?? "登录后查看云端记录")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if state.isAuthed {
                            Button("退出") { confirmingLogout = true }
                                .buttonStyle(.glass)
                        } else {
                            Button("登录") { state.showingLogin = true }
                                .buttonStyle(.glassProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("连接") {
                    Button {
                        draft = state.server
                        editing = .server
                    } label: {
                        row("云端服务器", state.server)
                    }
                    Button {
                        draft = state.device
                        editing = .device
                    } label: {
                        row("设备直连（局域网）", state.device.isEmpty ? "未设置" : state.device)
                    }
                }

                Section("外观") {
                    Picker("主题", selection: $state.theme) {
                        ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("关于") {
                    LabeledContent("版本", value: "\(Diagnostics.appVersion) (\(Diagnostics.buildNumber))")
                    LabeledContent("构建", value: Diagnostics.buildType)
                    LabeledContent("界面来源", value: "SwiftUI 原生 · iOS 26 Liquid Glass")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("我的")
            .confirmationDialog("退出登录？", isPresented: $confirmingLogout, titleVisibility: .visible) {
                Button("退出", role: .destructive) { state.signOut() }
                Button("取消", role: .cancel) {}
            }
            .alert(
                editing == .device ? "InkPi 设备地址（与手机在同一 Wi-Fi）" : "云端服务器地址",
                isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }),
                presenting: editing
            ) { target in
                TextField(target == .device ? "http://192.168.0.47:5000" : defaultServer, text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("取消", role: .cancel) {}
                Button("确定") {
                    switch target {
                    case .server:
                        state.setServer(draft)
                        Task { await state.checkServer() }
                    case .device:
                        state.setDevice(draft)
                        Task { await state.checkDevice() }
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}
