import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var state

    @State private var quality = "all"
    @State private var keyword = ""
    @State private var items: [ResultRecord] = []
    @State private var total = 0
    @State private var summary: JSONValue?
    @State private var loaded = false
    @State private var loadError: String?
    @State private var loadingMore = false
    @State private var editMode: EditMode = .inactive
    @State private var selected = Set<Int>()
    @State private var pendingDelete: [Int] = []

    private let filters: [(value: String, label: String)] = [("all", "全部"), ("good", "好"), ("medium", "中"), ("bad", "坏")]

    var body: some View {
        @Bindable var state = state
        NavigationStack(path: $state.historyPath) {
            List(selection: $selected) {
                Section {
                    summaryCard
                } footer: {
                    if let insight = summary?["insight"]?.string, !insight.isEmpty {
                        Text(insight)
                    }
                }

                Section {
                    if let loadError, items.isEmpty {
                        ContentUnavailableView {
                            Label("加载失败", systemImage: "exclamationmark.icloud")
                        } description: {
                            Text(loadError)
                        } actions: {
                            Button("重试") { Task { await load(reset: true) } }
                                .buttonStyle(.glass)
                        }
                    } else if !loaded {
                        HStack { Spacer(); ProgressView("加载中…"); Spacer() }
                            .listRowBackground(Color.clear)
                    } else if items.isEmpty {
                        ContentUnavailableView(
                            "还没有记录",
                            systemImage: "scroll",
                            description: Text("在 InkPi 上完成一次评测，这里会自动出现。")
                        )
                    } else {
                        ForEach(items) { record in
                            NavigationLink(value: record.id) {
                                HistoryRow(record: record, thumbURL: state.imageURL(record.id, "processed"))
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    pendingDelete = [record.id]
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                        if items.count < total {
                            Button {
                                Task { await load(reset: false) }
                            } label: {
                                HStack {
                                    Spacer()
                                    if loadingMore { ProgressView() } else { Text("加载更多") }
                                    Spacer()
                                }
                            }
                            .disabled(loadingMore)
                        }
                    }
                } header: {
                    if loaded && !items.isEmpty {
                        Text("共 \(total) 条")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, $editMode)
            .navigationTitle("评测记录")
            .searchable(text: $keyword, prompt: "搜索汉字")
            .safeAreaBar(edge: .top) {
                GlassChips(options: filters, selection: $quality)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
            }
            .toolbar { toolbar }
            .refreshable { await load(reset: true) }
            .task(id: "\(quality)|\(keyword)|\(state.historyVersion)|\(state.token)") {
                // Debounce typing like the web app's 350 ms timer.
                if loaded { try? await Task.sleep(for: .milliseconds(350)) }
                guard !Task.isCancelled else { return }
                await load(reset: true)
            }
            .confirmationDialog(
                "删除 \(pendingDelete.count) 条云端记录？此操作不可恢复。",
                isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    let ids = pendingDelete
                    Task { await delete(ids) }
                }
                Button("取消", role: .cancel) {}
            }
            .navigationDestination(for: Int.self) { id in
                ResultDetailView(id: id)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if editMode.isEditing {
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .destructive) {
                    pendingDelete = Array(selected)
                } label: {
                    Label("删除所选（\(selected.count)）", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                }
                .tint(.inkBad)
                .disabled(selected.isEmpty)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(editMode.isEditing ? "完成" : "选择") {
                withAnimation {
                    editMode = editMode.isEditing ? .inactive : .active
                    selected.removeAll()
                }
            }
            .disabled(items.isEmpty && !editMode.isEditing)
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await load(reset: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("刷新")
        }
    }

    private var summaryCard: some View {
        let s = summary
        let average = s?["average_score"]?.double.map { String(format: "%.1f", $0) } ?? "--"
        return HStack {
            stat(s?["total"]?.string ?? "--", "记录")
            Divider()
            stat(average, "平均分")
            Divider()
            stat(s?["quality_counts"]?["good"]?.string ?? (s == nil ? "--" : "0"), "优秀")
        }
        .padding(.vertical, 6)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func query(_ extra: [URLQueryItem]) -> String {
        var comps = URLComponents()
        comps.queryItems = extra + [
            URLQueryItem(name: "quality_level", value: quality),
            URLQueryItem(name: "keyword", value: keyword.trimmingCharacters(in: .whitespaces)),
        ]
        return comps.percentEncodedQuery ?? ""
    }

    private func load(reset: Bool) async {
        guard state.isAuthed else { return }
        let offset = reset ? 0 : items.count
        if !reset { loadingMore = true }
        defer { loadingMore = false }
        do {
            let listing = try await state.cloud.get("/api/results?" + query([
                URLQueryItem(name: "limit", value: "20"),
                URLQueryItem(name: "offset", value: String(offset)),
            ]))
            let page = listing["items"]?.array.map(ResultRecord.init(raw:)) ?? []
            if reset {
                let s = try await state.cloud.get("/api/results/summary?" + query([]))
                summary = s["summary"]
                items = page
                selected.formIntersection(page.map(\.id))
            } else {
                let known = Set(items.map(\.id))
                items += page.filter { !known.contains($0.id) }
            }
            total = listing["total"]?.int ?? items.count
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            if state.handleAuthError(error) { return }
            loadError = errorText(error)
            if !reset { state.show(errorText(error), error: true) }
        }
        loaded = true
    }

    private func delete(_ ids: [Int]) async {
        do {
            if ids.count == 1 {
                _ = try await state.cloud.delete("/api/results/\(ids[0])")
            } else {
                _ = try await state.cloud.post("/api/results/batch-delete", .object(["ids": .array(ids.map { .number(Double($0)) })]))
            }
            state.show("已删除 \(ids.count) 条")
            editMode = .inactive
            selected.removeAll()
            pendingDelete = []
            await load(reset: true)
        } catch {
            pendingDelete = []
            if !state.handleAuthError(error) { state.show(errorText(error), error: true) }
        }
    }
}

struct HistoryRow: View {
    var record: ResultRecord
    var thumbURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            CharacterThumb(record: record, url: thumbURL)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.character ?? "未识别").font(.inkSerif(18, relativeTo: .headline))
                    LevelBadge(key: record.qualityLevel)
                }
                Text("\(when(record.timestamp)) · \(record.deviceName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(record.score)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(record.level.tone)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
