import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var state

    private enum Mode: String, CaseIterable, Identifiable {
        case login, register
        var id: String { rawValue }
        var label: String { self == .login ? "登录" : "注册" }
    }

    private enum Field: Hashable { case username, displayName, password }

    @State private var mode: Mode = .login
    @State private var username = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var error = ""
    @State private var busy = false
    @State private var editingServer = false
    @State private var serverDraft = ""
    @FocusState private var focus: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            BrandMark(size: 52)
                            Text("InkPi").font(.largeTitle.weight(.bold))
                        }
                        Text("查看树莓派上的毛笔字评测记录")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    Picker("模式", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)

                    VStack(spacing: 0) {
                        field("用户名") {
                            TextField("至少 3 个字符", text: $username)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: .username)
                                .submitLabel(.next)
                                .onSubmit { focus = mode == .register ? .displayName : .password }
                        }
                        if mode == .register {
                            Divider().padding(.leading, 16)
                            field("昵称（可选）") {
                                TextField("显示在「我的」里", text: $displayName)
                                    .focused($focus, equals: .displayName)
                                    .submitLabel(.next)
                                    .onSubmit { focus = .password }
                            }
                        }
                        Divider().padding(.leading, 16)
                        field("密码") {
                            SecureField("至少 6 位", text: $password)
                                .textContentType(mode == .login ? .password : .newPassword)
                                .focused($focus, equals: .password)
                                .submitLabel(.go)
                                .onSubmit { Task { await submit() } }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))

                    if !error.isEmpty {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(Color.inkBad)
                            .transition(.opacity)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(mode == .login ? "登录" : "注册并登录")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(busy)

                    VStack(spacing: 14) {
                        Button {
                            serverDraft = state.server
                            editingServer = true
                        } label: {
                            Label("服务器：\(state.server)", systemImage: "server.rack")
                                .font(.footnote)
                                .lineLimit(1)
                        }
                        .buttonStyle(.glass)

                        GlassEffectContainer(spacing: 12) {
                            HStack(spacing: 12) {
                                Button { state.open(.setup) } label: {
                                    Label("设备配网", systemImage: "wifi")
                                }
                                .buttonStyle(.glass)
                                Button { state.open(.debug) } label: {
                                    Label("调试", systemImage: "ladybug")
                                }
                                .buttonStyle(.glass)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .animation(.smooth, value: mode)
                .animation(.smooth, value: error)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .background(alignment: .topTrailing) {
                // Content-layer decoration: a large faint 墨 behind the form.
                Text("墨")
                    .font(.inkSerif(260))
                    .foregroundStyle(Color.inkAccent.opacity(0.07))
                    .offset(x: 40, y: -30)
                    .accessibilityHidden(true)
            }
            .onChange(of: mode) { error = "" }
            .alert("云端服务器地址", isPresented: $editingServer) {
                TextField(defaultServer, text: $serverDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("取消", role: .cancel) {}
                Button("确定") {
                    state.setServer(serverDraft)
                    Task { await state.checkServer() }
                }
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func submit() async {
        let user = username.trimmingCharacters(in: .whitespaces)
        guard user.count >= 3 else { error = "用户名至少 3 个字符"; return }
        guard password.count >= 6 else { error = "密码至少 6 位"; return }
        busy = true
        defer { busy = false }
        do {
            if mode == .register {
                _ = try await state.cloud.post("/api/auth/register", .object([
                    "username": .string(user),
                    "password": .string(password),
                    "display_name": .string(displayName.trimmingCharacters(in: .whitespaces)),
                ]))
            }
            let data = try await state.cloud.post("/api/auth/login", .object([
                "username": .string(user),
                "password": .string(password),
            ]))
            guard let token = data["token"]?.string else { throw APIError(status: 0, message: "登录响应缺少 token") }
            state.signedIn(token: token, user: data["user"])
            state.show("欢迎，\(state.displayName ?? user)")
        } catch {
            self.error = errorText(error)
        }
    }
}
