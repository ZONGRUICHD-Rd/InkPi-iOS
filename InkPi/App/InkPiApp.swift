import SwiftUI

@main
struct InkPiApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .tint(.inkAccent)
                .preferredColorScheme(state.theme.scheme)
                .onAppear { appLog.info("launch \(Diagnostics.appVersion, privacy: .public) (\(Diagnostics.buildNumber, privacy: .public))") }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack(alignment: .top) {
            if state.showingLogin {
                LoginView()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .id(state.reloadID)
        .animation(.smooth, value: state.showingLogin)
        .overlay(alignment: .top) {
            if let toast = state.toast {
                ToastView(toast: toast)
                    .padding(.top, 8)
                    .glassEffectTransition(.materialize)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { state.toast = nil }
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(toast.isError ? 4.2 : 2.6))
                        if state.toast?.id == toast.id { state.toast = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: state.toast)
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        TabView(selection: Binding(get: { state.tab }, set: { state.open($0) })) {
            Tab("记录", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView()
            }
            Tab("配网", systemImage: "wifi", value: AppTab.setup) {
                SetupView()
            }
            Tab("调试", systemImage: "ladybug", value: AppTab.debug) {
                DebugView()
            }
            Tab("我的", systemImage: "person.crop.circle", value: AppTab.me) {
                MeView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            ConnectionAccessory()
        }
    }
}

/// Bottom accessory above the tab bar: live cloud / device reachability,
/// tap to re-check. Collapses into the minimized tab bar when scrolling.
struct ConnectionAccessory: View {
    @Environment(AppState.self) private var state
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var cloudOK: Bool?
    @State private var deviceOK: Bool?
    @State private var checking = false

    var body: some View {
        Button {
            Task { await check() }
        } label: {
            HStack(spacing: 10) {
                dot(cloudOK)
                Text(placement == .inline ? "云端" : "云端 \(host(state.server))")
                    .lineLimit(1)
                if !state.device.isEmpty {
                    dot(deviceOK)
                    Text(placement == .inline ? "设备" : "设备 \(host(state.device))")
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if checking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            .padding(.horizontal, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("连接状态，轻点重新检测")
        .task(id: "\(state.server)|\(state.device)") { await check() }
    }

    private func dot(_ ok: Bool?) -> some View {
        Circle()
            .fill(ok == nil ? Color.secondary : ok! ? Color.inkGood : Color.inkBad)
            .frame(width: 7, height: 7)
    }

    private func host(_ url: String) -> String {
        guard let comps = URLComponents(string: url), let host = comps.host else { return url }
        return comps.port.map { "\(host):\($0)" } ?? host
    }

    private func check() async {
        checking = true
        defer { checking = false }
        cloudOK = (try? await state.cloud.get("/api/health", timeout: 6)) != nil
        if state.device.isEmpty {
            deviceOK = nil
        } else {
            deviceOK = (try? await state.deviceClient.get("/api/device/status", timeout: 6)) != nil
        }
    }
}
