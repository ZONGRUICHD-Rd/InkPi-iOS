import Foundation
import SwiftUI
import UIKit

// MARK: palette (tokens from ui/inkpi-ui.css)

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    static let inkAccent = Color(light: 0xC96442, dark: 0xD97757)
    static let inkGood = Color(light: 0x5B7B3A, dark: 0x9CC06E)
    static let inkMid = Color(light: 0xA8741A, dark: 0xE0B45A)
    static let inkBad = Color(light: 0xB5453A, dark: 0xE5867A)
}

extension Font {
    /// Song/serif face for the written characters (the web UI uses Noto Serif CJK).
    static func inkSerif(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("STSongti-SC-Bold", size: size, relativeTo: style)
    }
}

// MARK: quality levels & dimensions (InkUI.level / DIMENSIONS)

struct Level {
    var key: String
    var label: String
    var word: String
    var tone: Color

    static func of(_ key: String?) -> Level {
        switch key {
        case "good": Level(key: "good", label: "好", word: "优秀", tone: .inkGood)
        case "bad": Level(key: "bad", label: "坏", word: "待提升", tone: .inkBad)
        default: Level(key: "medium", label: "中", word: "良好", tone: .inkMid)
        }
    }
}

let dimensionNames: [(key: String, name: String)] = [
    ("stroke", "笔画"),
    ("structure", "结构"),
    ("stability", "稳定"),
    ("integrity", "完整"),
]

func pct(_ value: Double?) -> String {
    guard let value else { return "--" }
    return "\(Int((value * 100).rounded()))%"
}

private let isoFull: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private let localNoZone: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return f
}()

private let hourMinute: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "HH:mm"
    return f
}()

func parseTimestamp(_ raw: String?) -> Date? {
    guard var s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
    s = s.replacingOccurrences(of: " ", with: "T")
    s = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    if s.hasSuffix("Z") || s.range(of: #"[+-]\d\d:?\d\d$"#, options: .regularExpression) != nil {
        return isoFull.date(from: s)
    }
    return localNoZone.date(from: s)
}

/// `InkUI.when`: 今天 HH:mm, otherwise M月d日 HH:mm.
func when(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "--" }
    guard let date = parseTimestamp(raw) else { return raw }
    let hm = hourMinute.string(from: date)
    if Calendar.current.isDateInToday(date) { return "今天 \(hm)" }
    let c = Calendar.current.dateComponents([.month, .day], from: date)
    return "\(c.month ?? 0)月\(c.day ?? 0)日 \(hm)"
}

// MARK: result record

/// One evaluation result as returned by `/api/results` (kept as raw JSON so
/// the debug fold can show every field).
struct ResultRecord: Identifiable, Hashable {
    var raw: JSONValue

    var id: Int { raw["id"]?.int ?? 0 }
    var character: String? { raw["character_name"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    var score: Int { raw["total_score"]?.int ?? 0 }
    var qualityLevel: String? { raw["quality_level"]?.string }
    var level: Level { .of(qualityLevel) }
    var timestamp: String? { raw["timestamp"]?.string }
    var deviceName: String { raw["device_name"]?.string ?? "" }
    var styleLabel: String { raw["calligraphy_style_label"]?.string ?? "" }
    var feedback: String { raw["feedback"]?.string ?? "" }
    var ocrConfidence: Double? { raw["ocr_confidence"]?.double }
    var qualityConfidence: Double? { raw["quality_confidence"]?.double }
    var localRecordID: String { raw["local_record_id"]?.string ?? "--" }
    var scoreDebug: JSONValue { raw["score_debug"] ?? .null }
    var hasProcessed: Bool { raw["images"]?["processed"]?.bool ?? false }
    var hasOriginal: Bool { raw["images"]?["original"]?.bool ?? false }

    var dimensions: [(name: String, value: Int)]? {
        guard let scores = raw["dimension_scores"], !scores.isNull else { return nil }
        let items = dimensionNames.compactMap { d -> (name: String, value: Int)? in
            guard let v = scores[d.key]?.double else { return nil }
            return (d.name, max(0, min(100, Int(v.rounded()))))
        }
        return items.isEmpty ? nil : items
    }

    /// `InkUI.dimSummary`.
    var dimensionSummary: String {
        guard let items = dimensions else { return "" }
        let sorted = items.sorted { $0.value > $1.value }
        return "\(sorted.first!.name)最好，\(sorted.last!.name)可再加强"
    }
}
