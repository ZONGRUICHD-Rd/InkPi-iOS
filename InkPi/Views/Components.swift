import SwiftUI

/// The 墨 brand tile used on the login screen and the 我的 card.
struct BrandMark: View {
    var text = "墨"
    var size: CGFloat = 40

    var body: some View {
        Text(text)
            .font(.inkSerif(size * 0.5))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.inkAccent.gradient, in: .rect(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// `InkUI.levelBadge`.
struct LevelBadge: View {
    var key: String?

    var body: some View {
        let level = Level.of(key)
        Text(level.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(level.tone)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(level.tone.opacity(0.14), in: .capsule)
            .accessibilityLabel("等级 \(level.word)")
    }
}

/// `InkUI.scoreRing`.
struct ScoreRing: View {
    var score: Int
    var levelKey: String?
    var size: CGFloat = 120

    var body: some View {
        let level = Level.of(levelKey)
        let value = Double(max(0, min(100, score))) / 100
        let line = max(6, size * 0.075)
        ZStack {
            Circle().stroke(.quaternary, lineWidth: line)
            Circle()
                .trim(from: 0, to: value)
                .stroke(level.tone, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(level.word).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("总分 \(score)，\(level.word)")
    }
}

/// `InkUI.dims`: four horizontal bars.
struct DimensionBars: View {
    var items: [(name: String, value: Int)]?

    var body: some View {
        if let items {
            VStack(spacing: 10) {
                ForEach(items, id: \.name) { item in
                    HStack(spacing: 10) {
                        Text(item.name).font(.subheadline).frame(width: 36, alignment: .leading)
                        ProgressView(value: Double(item.value), total: 100)
                            .tint(.inkAccent)
                        Text("\(item.value)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .frame(width: 30, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } else {
            Text("这条记录没有四维评分").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// Wi-Fi strength bars from the setup flow.
struct SignalBars: View {
    var signal: Int

    var body: some View {
        let level = signal >= 75 ? 4 : signal >= 50 ? 3 : signal >= 25 ? 2 : 1
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { n in
                RoundedRectangle(cornerRadius: 1)
                    .fill(n <= level ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 3, height: CGFloat(n * 3 + 2))
            }
        }
        .frame(width: 20, height: 14, alignment: .bottom)
        .accessibilityLabel("信号 \(signal)")
    }
}

/// Monospaced, selectable output block for JSON and logs.
struct CodeBlock: View {
    var text: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxHeight: 360)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10, style: .continuous))
    }
}

/// Coloured info/warning/error strip (`.banner` in the web UI).
struct Banner: View {
    enum Tone { case ok, warn, err }
    var tone: Tone
    var text: Text

    init(_ tone: Tone, _ text: Text) {
        self.tone = tone
        self.text = text
    }

    init(_ tone: Tone, _ string: String) {
        self.init(tone, Text(string))
    }

    private var color: Color {
        switch tone {
        case .ok: .inkGood
        case .warn: .inkMid
        case .err: .inkBad
        }
    }

    private var symbol: String {
        switch tone {
        case .ok: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .err: "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            text.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(color.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

/// Thumbnail of the processed image, falling back to the recognised character.
struct CharacterThumb: View {
    var record: ResultRecord
    var url: URL?

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if record.hasProcessed, let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Text(record.character ?? "?").font(.inkSerif(24)).foregroundStyle(.secondary)
    }
}

/// Transient message. Toasts float above content, so they are a glass layer.
struct ToastView: View {
    var toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? Color.inkBad : Color.inkGood)
            Text(toast.message).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 24)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Glass filter chips (全部 / 好 / 中 / 坏). The selected chip is tinted, and
/// the shared container lets the shapes blend and morph as the choice moves.
struct GlassChips<Value: Hashable>: View {
    var options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(options, id: \.value) { option in
                    let on = option.value == selection
                    Button {
                        withAnimation(.smooth(duration: 0.3)) { selection = option.value }
                    } label: {
                        Text(option.label)
                            .font(.subheadline.weight(on ? .semibold : .regular))
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(on ? .regular.tint(.inkAccent).interactive() : .regular.interactive(), in: .capsule)
                    .glassEffectID(option.label, in: glass)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}
