import SwiftUI

struct ResultDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var id: Int

    @State private var record: ResultRecord?
    @State private var loadError: String?
    @State private var imageKind = "processed"
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            if let record {
                content(record)
            } else if let loadError {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("重试") { Task { await load() } }.buttonStyle(.glass)
                }
            } else {
                ProgressView("加载中…")
            }
        }
        .navigationTitle("评测详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let record {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: record.raw.pretty, subject: Text("InkPi 评测 #\(record.id)")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("分享原始数据")
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.inkBad)
                    .accessibilityLabel("删除这条记录")
                }
            }
        }
        .confirmationDialog("删除这条云端记录？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { Task { await delete() } }
            Button("取消", role: .cancel) {}
        }
        .task { await load() }
    }

    private func content(_ r: ResultRecord) -> some View {
        let kinds = [
            ImageKind(key: "processed", label: "处理后", available: r.hasProcessed),
            ImageKind(key: "original", label: "原图", available: r.hasOriginal),
        ].filter(\.available)
        return List {
            Section {
                HStack(spacing: 20) {
                    ScoreRing(score: r.score, levelKey: r.qualityLevel, size: 120)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(r.character ?? "?").font(.inkSerif(52, relativeTo: .largeTitle))
                        HStack(spacing: 6) {
                            LevelBadge(key: r.qualityLevel)
                            Text(r.styleLabel).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text("\(when(r.timestamp)) · \(r.deviceName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }

            if !kinds.isEmpty {
                Section {
                    if kinds.count > 1 {
                        Picker("图像", selection: $imageKind) {
                            ForEach(kinds, id: \.key) { Text($0.label).tag($0.key) }
                        }
                        .pickerStyle(.segmented)
                        .listRowSeparator(.hidden)
                    }
                    let kind = kinds.contains { $0.key == imageKind } ? imageKind : kinds[0].key
                    AsyncImage(url: state.imageURL(r.id, kind)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure:
                            Label("图像加载失败", systemImage: "photo.badge.exclamationmark")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 160)
                        default:
                            ProgressView().frame(maxWidth: .infinity, minHeight: 220)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .id(kind)
                    .accessibilityLabel("作品图像")
                } header: {
                    Text("作品图像")
                }
            }

            Section {
                DimensionBars(items: r.dimensions)
                    .padding(.vertical, 4)
            } header: {
                Text("四维评分")
            } footer: {
                if !r.dimensionSummary.isEmpty { Text(r.dimensionSummary) }
            }

            Section("评语") {
                Text(r.feedback.isEmpty ? "--" : r.feedback)
                    .textSelection(.enabled)
            }

            Section("识别与置信度") {
                LabeledContent("识别", value: pct(r.ocrConfidence))
                LabeledContent("等级置信", value: pct(r.qualityConfidence))
                LabeledContent("等级", value: "\(r.level.word)（\(r.level.label)）")
                LabeledContent("设备记录号", value: "#\(r.localRecordID)")
                LabeledContent("云端编号", value: "#\(r.id)")
                DisclosureGroup("评分调试数据") {
                    CodeBlock(text: r.scoreDebug.pretty)
                }
                DisclosureGroup("原始 JSON") {
                    CodeBlock(text: r.raw.pretty)
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("删除这条记录", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func load() async {
        do {
            let data = try await state.cloud.get("/api/results/\(id)")
            guard let raw = data["result"] else { throw APIError(status: 0, message: "响应缺少 result") }
            record = ResultRecord(raw: raw)
            loadError = nil
        } catch {
            if state.handleAuthError(error) { return }
            loadError = errorText(error)
        }
    }

    private func delete() async {
        do {
            _ = try await state.cloud.delete("/api/results/\(id)")
            state.show("已删除")
            state.historyVersion += 1
            dismiss()
        } catch {
            if !state.handleAuthError(error) { state.show(errorText(error), error: true) }
        }
    }
}

private struct ImageKind {
    var key: String
    var label: String
    var available: Bool
}
