import CMbpCore
import Foundation

/// スナップショット群から「キャラを動かす1つの数値」を決める純関数群。
///
/// 最大値を採るのは、上限に当たる前に気づくのが目的だから。5時間枠だけ見ていると、
/// 週枠がじわじわ埋まって不意打ちになるケースを取り逃す。
public enum AIUsageAggregator {
    /// 上限到達の報せを「今の話」として扱う猶予。これを過ぎたら表示だけ残して駆動には使わない。
    public static let reachedLimitFreshness: TimeInterval = 5 * 60 * 60

    /// 枠の実効使用率。リセット時刻を過ぎた枠は 0 とみなす（新しい枠に切り替わっている）。
    public static func effectiveUsedPercentage(_ window: AIUsageWindow, now: Date) -> Double {
        mbp_effective_used(window.usedPercentage, window.resetsAt?.timeIntervalSince1970 ?? .nan, now.timeIntervalSince1970)
    }

    /// 上限に当たったという報せを、枠と同じ土俵に乗せるための疑似枠。
    ///
    /// 上限到達時は枠の数値が消える（両方 null になる）ので、枠だけ見ていると
    /// 「一番詰まっている状態」なのにキャラが休んでしまう。直近の報せは 100% として駆動する。
    public static func reachedLimitWindow(_ snapshot: AIUsageSnapshot, now: Date) -> AIUsageWindow? {
        guard snapshot.rateLimitReachedType != nil else { return nil }
        let observed = snapshot.noteObservedAt ?? snapshot.observedAt
        // 未来の時刻（時計ずれ・タイムゾーン事故）は「直近」と見なさない。0 以上の経過だけを通す。
        guard mbp_limit_is_fresh(observed.timeIntervalSince1970, now.timeIntervalSince1970) != 0 else { return nil }
        // 英語のIDは note 行に残す。見出しに出るのは人が読める1語だけにする。
        return AIUsageWindow(label: "上限到達", usedPercentage: 100, resetsAt: nil)
    }

    /// そのスナップショットが差し出す枠すべて（実際の枠＋上限到達の疑似枠）。
    public static func drivingWindows(_ snapshot: AIUsageSnapshot, now: Date) -> [AIUsageWindow] {
        snapshot.windows + (reachedLimitWindow(snapshot, now: now).map { [$0] } ?? [])
    }

    public static func driveValue(
        snapshots: [AIUsageSnapshot],
        enabled: Set<AIUsageProvider>,
        now: Date
    ) -> Double? {
        bindingWindow(snapshots: snapshots, enabled: enabled, now: now)
            .map { effectiveUsedPercentage($0.window, now: now) }
    }

    /// 最大値を出した枠。popover の見出し「AI残量 88%（Codex 7日）」に使う。
    public static func bindingWindow(
        snapshots: [AIUsageSnapshot],
        enabled: Set<AIUsageProvider>,
        now: Date
    ) -> (snapshot: AIUsageSnapshot, window: AIUsageWindow)? {
        var best: (snapshot: AIUsageSnapshot, window: AIUsageWindow)?
        var bestValue = -Double.infinity
        for snapshot in snapshots where enabled.contains(snapshot.provider) {
            for window in drivingWindows(snapshot, now: now) {
                let value = effectiveUsedPercentage(window, now: now)
                if value > bestValue {
                    bestValue = value
                    best = (snapshot, window)
                }
            }
        }
        return best
    }

    /// 明細行に出す使用率。見出し（実効値）と食い違わないよう、実効値を主にして元の値を括弧で添える。
    public static func formatUsedPercentage(_ window: AIUsageWindow, now: Date) -> String {
        let effective = Int(effectiveUsedPercentage(window, now: now).rounded())
        let raw = window.usedPercentage.isFinite ? Int(window.usedPercentage.rounded()) : 0
        guard effective != raw else { return "\(effective)%" }
        if let resetsAt = window.resetsAt, resetsAt <= now {
            return "\(effective)%（リセット済み・元 \(raw)%）"
        }
        return "\(effective)%（元 \(raw)%）"
    }

    /// 同日なら "14:30 リセット"、翌日以降なら "9/20 14:30 リセット"、過ぎていれば "リセット済み"。
    public static func formatResetsAt(
        _ date: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        guard let date else { return "" }
        if date <= now { return "リセット済み" }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let month = parts.month, let day = parts.day,
              let hour = parts.hour, let minute = parts.minute
        else { return "" }
        let clock = String(format: "%02d:%02d", hour, minute)
        if calendar.isDate(date, inSameDayAs: now) { return "\(clock) リセット" }
        return "\(month)/\(day) \(clock) リセット"
    }

    /// statusLine に出す1行。例: "Claude 5時間 23% · 7日 41%"。枠が無ければ空文字。
    public static func formatStatusLine(_ snapshot: AIUsageSnapshot?) -> String {
        guard let snapshot else { return "" }
        guard !snapshot.windows.isEmpty else { return snapshot.note ?? "" }
        let body = snapshot.windows
            .map { "\($0.label) \(Int($0.usedPercentage.rounded()))%" }
            .joined(separator: " · ")
        return "\(snapshot.provider.shortName) \(body)"
    }
}
