import Foundation

/// キャラを動かす指標。CPU使用率か、AIコーディングツールの使用枠か。
public enum MetricSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu
    case aiUsage

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cpu: "CPU"
        case .aiUsage: "AI使用率"
        }
    }
}

public enum AIUsageProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// statusLine の1行など、幅が限られる場所で使う短い名前。
    public var shortName: String {
        switch self {
        case .claudeCode: "Claude"
        case .codex: "Codex"
        }
    }
}

/// 使用枠ひとつ（5時間枠・7日枠など）。
public struct AIUsageWindow: Equatable, Sendable {
    public let label: String
    public let usedPercentage: Double
    public let resetsAt: Date?
    /// 枠の長さ（分）。「短い枠／長い枠」の並べ替えに使う。分からない枠（支出上限など）は nil。
    public let durationMinutes: Double?

    public init(
        label: String,
        usedPercentage: Double,
        resetsAt: Date?,
        durationMinutes: Double? = nil
    ) {
        self.label = label
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
        self.durationMinutes = durationMinutes
    }
}

/// 1プロファイル（設定ホーム1つ）ぶんの読み取り結果。
public struct AIUsageSnapshot: Equatable, Sendable {
    public let provider: AIUsageProvider
    /// 設定ホームの basename。例 ".claude-work" ".codex-personal"
    public let profileName: String
    public let windows: [AIUsageWindow]
    public let observedAt: Date
    /// 枠が読めない理由など、そのまま画面に出す短い説明。
    public let note: String?
    public let sourcePath: String
    /// model／context% など、表示に添えるだけの補足。
    public let extras: [String: String]

    public init(
        provider: AIUsageProvider,
        profileName: String,
        windows: [AIUsageWindow],
        observedAt: Date,
        note: String? = nil,
        sourcePath: String,
        extras: [String: String] = [:]
    ) {
        self.provider = provider
        self.profileName = profileName
        self.windows = windows
        self.observedAt = observedAt
        self.note = note
        self.sourcePath = sourcePath
        self.extras = extras
    }
}

enum AIUsageJSON {
    /// キー欠落・型違い・null を全部「無い」として扱う。設定ファイルは人が触るので落ちない方を優先する。
    static func object(_ any: Any?) -> [String: Any]? {
        any as? [String: Any]
    }

    static func number(_ any: Any?) -> Double? {
        if let value = any as? Double { return value.isFinite ? value : nil }
        if let value = any as? Int { return Double(value) }
        if let value = any as? NSNumber { return value.doubleValue.isFinite ? value.doubleValue : nil }
        return nil
    }

    static func string(_ any: Any?) -> String? {
        guard let value = any as? String, !value.isEmpty else { return nil }
        return value
    }

    /// epoch 秒（整数・小数どちらもありうる）を Date に。
    ///
    /// ミリ秒で書かれている実装があるので、秒として解釈すると 5000 年後になる値は 1000 で割る。
    /// 分岐点の 1e11 は西暦 5138 年（秒読み）／1973 年（ミリ秒読み）なので、実用上の日付と衝突しない。
    static func epochDate(_ any: Any?) -> Date? {
        guard let raw = number(any), raw > 0 else { return nil }
        let seconds = raw > 1e11 ? raw / 1_000 : raw
        return Date(timeIntervalSince1970: seconds)
    }
}

public extension AIUsageSnapshot {
    /// Codex が返す上限到達の理由（`workspace_member_credits_depleted` など）。
    static let rateLimitReachedTypeKey = "rate_limit_reached_type"
    /// 上限到達を観測した時刻（ISO8601）。枠を古い行から採ったときは observedAt と別になる。
    static let noteObservedAtKey = "note_observed_at"

    var rateLimitReachedType: String? { extras[Self.rateLimitReachedTypeKey] }

    var noteObservedAt: Date? {
        guard let text = extras[Self.noteObservedAtKey] else { return nil }
        return ISO8601TimestampParser().date(from: text)
    }
}
