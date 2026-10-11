import Foundation

/// メニューバーのキャラ画像の右に出す、2行ぶんの数字を組み立てる。
///
/// キャラの速さは「いちばん詰まっている枠」1つしか表せない。本人の使い方では
/// Claude Code と Codex を両方、しかも 5時間枠と週枠を両方見たいので、
/// クリックせずに 4 つの数字が読めることをこの関数で担保する。
public enum MenuBarReadout {
    /// プロバイダ名の桁。2行の数字を縦に揃えるために左寄せで埋める。
    static let nameWidth = 6
    /// 数字の桁。100% が入っても列が動かないように 3 桁で右寄せする。
    static let valueWidth = 3
    static let missingValue = "--"
    static let reachedLimitText = "上限"

    /// 1行＝1プロバイダ。例: `Claude  23  41` / `Codex   17  88` / `Claude  --  --`。
    public static func rows(
        snapshots: [AIUsageSnapshot],
        enabled: Set<AIUsageProvider>,
        now: Date
    ) -> [String] {
        AIUsageProvider.allCases
            .filter { enabled.contains($0) }
            .map { provider in
                let name = padded(provider.shortName)
                guard let snapshot = mostConstrained(snapshots, provider: provider, now: now) else {
                    return "\(name) \(value(nil)) \(value(nil))"
                }
                // 上限に当たっている間は、残っている枠の数字より「上限」の一語が先に伝わるべき。
                // 枠が残っていても（古い枠が消えずにいても）こちらを出す。内訳はツールチップにある。
                if AIUsageAggregator.reachedLimitWindow(snapshot, now: now) != nil {
                    return "\(name) \(reachedLimitText)"
                }
                let slots = slots(snapshot.windows)
                return "\(name) \(value(slots.short, now: now)) \(value(slots.long, now: now))"
            }
    }

    /// ツールチップには省略せず全部出す（メニューバーは 2 行に絞っているぶん、ここで補う）。
    public static func tooltip(
        snapshots: [AIUsageSnapshot],
        enabled: Set<AIUsageProvider>,
        now: Date
    ) -> String {
        var lines: [String] = []
        for provider in AIUsageProvider.allCases where enabled.contains(provider) {
            let forProvider = snapshots.filter { $0.provider == provider }
            guard !forProvider.isEmpty else {
                lines.append("\(provider.displayName): データなし")
                continue
            }
            for snapshot in forProvider {
                lines.append("\(provider.displayName)（\(snapshot.profileName)）")
                for window in snapshot.windows {
                    let resets = AIUsageAggregator.formatResetsAt(window.resetsAt, now: now)
                    lines.append("  \(window.label) "
                        + AIUsageAggregator.formatUsedPercentage(window, now: now)
                        + (resets.isEmpty ? "" : "・\(resets)"))
                }
                if snapshot.windows.isEmpty { lines.append("  枠の情報なし") }
                if let note = snapshot.note { lines.append("  \(note)") }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 同じプロバイダに複数プロファイルがあるときは、いちばん詰まっている方を出す（駆動値と同じ基準）。
    public static func mostConstrained(
        _ snapshots: [AIUsageSnapshot],
        provider: AIUsageProvider,
        now: Date
    ) -> AIUsageSnapshot? {
        snapshots
            .filter { $0.provider == provider }
            .max { left, right in peak(left, now: now) < peak(right, now: now) }
    }

    private static func peak(_ snapshot: AIUsageSnapshot, now: Date) -> Double {
        AIUsageAggregator.drivingWindows(snapshot, now: now)
            .map { AIUsageAggregator.effectiveUsedPercentage($0, now: now) }
            .max() ?? -1
    }

    /// 短い枠と長い枠を選ぶ。長さが分かっている枠を優先し、余った枠だけが空き slot を埋める。
    public static func slots(_ windows: [AIUsageWindow]) -> (short: AIUsageWindow?, long: AIUsageWindow?) {
        let known = windows.indices
            .filter { windows[$0].durationMinutes != nil }
            // 長さが同じ枠が来ても並びが揺れないよう、元の配列順を第2キーにする。
            .sorted { left, right in
                let leftMinutes = windows[left].durationMinutes ?? 0
                let rightMinutes = windows[right].durationMinutes ?? 0
                return leftMinutes == rightMinutes ? left < right : leftMinutes < rightMinutes
            }
        let unknown = windows.indices.filter { windows[$0].durationMinutes == nil }

        let shortIndex = known.first ?? unknown.first
        let longIndex = (known.count >= 2 ? known.last : nil)
            ?? unknown.first { $0 != shortIndex }
        return (shortIndex.map { windows[$0] }, longIndex.map { windows[$0] })
    }

    private static func value(_ window: AIUsageWindow?, now: Date = Date()) -> String {
        guard let window else { return alignRight(missingValue) }
        let percentage = Int(AIUsageAggregator.effectiveUsedPercentage(window, now: now).rounded())
        return alignRight("\(percentage)")
    }

    private static func padded(_ name: String) -> String {
        name.count >= nameWidth
            ? name
            : name + String(repeating: " ", count: nameWidth - name.count)
    }

    private static func alignRight(_ text: String) -> String {
        text.count >= valueWidth
            ? text
            : String(repeating: " ", count: valueWidth - text.count) + text
    }

    /// メニューバー画像の寸法。実際の描画は AppKit 側だが、数値はここに集めてテストする。
    ///
    /// `NSStatusBarButton` の `attributedTitle` に 2 行を入れると上段のグリフ上端が切れた
    /// （実機 2026-09-16）。ボタンに文字を描かせず1枚の画像に合成する方式へ変えたので、
    /// ベースラインを自分で決める必要がある。9pt の cap height は約 6.4pt。
    public enum Layout {
        public static let height: Double = 22
        /// ペット画像に充てる幅。従来のステータス項目の長さと同じにして、位置を変えない。
        public static let petSlotWidth: Double = 44
        public static let gap: Double = 6
        public static let trailingPadding: Double = 4
        public static let fontSize: Double = 9

        /// 2 行のときのベースライン（原点は左下）。上段は 12.0〜18.4、下段は 2.5〜8.9 に収まる。
        public static let topBaseline: Double = 12.0
        public static let bottomBaseline: Double = 2.5
        /// 1 行だけのときは縦中央に1本。
        public static let singleBaseline: Double = 6.5

        public static func baselines(rowCount: Int) -> [Double] {
            switch rowCount {
            case ..<1: []
            case 1: [singleBaseline]
            default: [topBaseline, bottomBaseline]
            }
        }

        /// 行が無ければペットだけ＝従来どおりの 44pt。
        public static func width(textWidth: Double, rowCount: Int) -> Double {
            guard rowCount > 0 else { return petSlotWidth }
            return petSlotWidth + gap + max(textWidth, 0).rounded(.up) + trailingPadding
        }

        public static func textOriginX() -> Double { petSlotWidth + gap }
    }
}
