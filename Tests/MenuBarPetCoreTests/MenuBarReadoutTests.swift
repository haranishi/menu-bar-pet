import Foundation
import MenuBarPetCore

private let future = referenceNow.addingTimeInterval(3_600)

private func snapshot(
    provider: AIUsageProvider,
    profileName: String,
    windows: [AIUsageWindow],
    note: String? = nil,
    reachedType: String? = nil,
    noteAgeHours: Double = 1
) -> AIUsageSnapshot {
    var extras: [String: String] = [:]
    if let reachedType {
        extras[AIUsageSnapshot.rateLimitReachedTypeKey] = reachedType
        extras[AIUsageSnapshot.noteObservedAtKey] = ISO8601DateFormatter()
            .string(from: referenceNow.addingTimeInterval(-noteAgeHours * 3_600))
    }
    return AIUsageSnapshot(
        provider: provider,
        profileName: profileName,
        windows: windows,
        observedAt: referenceNow,
        note: note,
        sourcePath: "\(provider.rawValue)-\(profileName)",
        extras: extras
    )
}

private func window(
    _ label: String,
    _ used: Double,
    minutes: Double?,
    resetsAt: Date? = future
) -> AIUsageWindow {
    AIUsageWindow(label: label, usedPercentage: used, resetsAt: resetsAt, durationMinutes: minutes)
}

let menuBarReadoutTests: [TestCase] = [
    TestCase(name: "Readout shows one line per provider with the short window first") {
        let claude = snapshot(
            provider: .claudeCode,
            profileName: ".claude-work",
            windows: [window("7日", 41, minutes: 10_080), window("5時間", 23, minutes: 300)]
        )
        let codex = snapshot(
            provider: .codex,
            profileName: ".codex-work",
            windows: [window("5時間", 17, minutes: 300), window("7日", 88, minutes: 10_080)]
        )
        let rows = MenuBarReadout.rows(
            snapshots: [codex, claude],
            enabled: Set(AIUsageProvider.allCases),
            now: referenceNow
        )
        try require(rows == ["Claude  23  41", "Codex   17  88"], "got \(rows)")
        // 並び順が逆に届いても、短い枠が先・列幅も揃う。
        try require(rows.allSatisfy { $0.count == rows[0].count }, "rows must line up")
    },
    TestCase(name: "Readout marks a missing window and missing data with dashes") {
        let single = snapshot(
            provider: .claudeCode,
            profileName: ".claude",
            windows: [window("5時間", 7, minutes: 300)]
        )
        let rows = MenuBarReadout.rows(
            snapshots: [single],
            enabled: Set(AIUsageProvider.allCases),
            now: referenceNow
        )
        try require(rows == ["Claude   7  --", "Codex   --  --"], "got \(rows)")

        let empty = MenuBarReadout.rows(
            snapshots: [],
            enabled: Set(AIUsageProvider.allCases),
            now: referenceNow
        )
        try require(empty == ["Claude  --  --", "Codex   --  --"], "got \(empty)")
    },
    TestCase(name: "Readout reports effective percentages, not stale raw ones") {
        let expired = snapshot(
            provider: .codex,
            profileName: ".codex",
            windows: [
                window("5時間", 99, minutes: 300, resetsAt: referenceNow.addingTimeInterval(-1)),
                window("7日", 32, minutes: 10_080),
            ]
        )
        let rows = MenuBarReadout.rows(snapshots: [expired], enabled: [.codex], now: referenceNow)
        try require(rows == ["Codex    0  32"], "expired windows read as zero: \(rows)")
    },
    TestCase(name: "Readout says 上限 when the limit was hit and no window survives") {
        let reached = snapshot(
            provider: .codex,
            profileName: ".codex-work",
            windows: [],
            note: "クレジット切れ（workspace_member_credits_depleted）",
            reachedType: "workspace_member_credits_depleted"
        )
        try require(
            MenuBarReadout.rows(snapshots: [reached], enabled: [.codex], now: referenceNow)
                == ["Codex  上限"],
            "got \(MenuBarReadout.rows(snapshots: [reached], enabled: [.codex], now: referenceNow))"
        )

        // 古い枠が残っていても「上限」が勝つ。数字だけ見せると、上限に当たったことを見落とす。
        let reachedWithWindows = snapshot(
            provider: .codex,
            profileName: ".codex-work",
            windows: [window("5時間", 0, minutes: 300), window("7日", 100, minutes: 10_080)],
            note: "クレジット切れ（workspace_member_credits_depleted）",
            reachedType: "workspace_member_credits_depleted"
        )
        try require(
            MenuBarReadout.rows(snapshots: [reachedWithWindows], enabled: [.codex], now: referenceNow)
                == ["Codex  上限"],
            "got \(MenuBarReadout.rows(snapshots: [reachedWithWindows], enabled: [.codex], now: referenceNow))"
        )

        // 5 時間を過ぎた上限は数字に戻る（駆動値と同じ鮮度規則）。
        let stale = snapshot(
            provider: .codex,
            profileName: ".codex-work",
            windows: [window("5時間", 4, minutes: 300), window("7日", 61, minutes: 10_080)],
            note: "クレジット切れ（workspace_member_credits_depleted）",
            reachedType: "workspace_member_credits_depleted",
            noteAgeHours: 6
        )
        try require(
            MenuBarReadout.rows(snapshots: [stale], enabled: [.codex], now: referenceNow)
                == ["Codex    4  61"],
            "got \(MenuBarReadout.rows(snapshots: [stale], enabled: [.codex], now: referenceNow))"
        )
    },
    TestCase(name: "Readout picks the most constrained profile of a provider") {
        let relaxed = snapshot(
            provider: .codex,
            profileName: ".codex-personal",
            windows: [window("5時間", 5, minutes: 300), window("7日", 32, minutes: 10_080)]
        )
        let busy = snapshot(
            provider: .codex,
            profileName: ".codex-work",
            windows: [window("5時間", 17, minutes: 300), window("7日", 88, minutes: 10_080)]
        )
        let rows = MenuBarReadout.rows(
            snapshots: [relaxed, busy],
            enabled: [.codex],
            now: referenceNow
        )
        try require(rows == ["Codex   17  88"], "the fullest profile wins: \(rows)")
        try require(
            MenuBarReadout.mostConstrained([relaxed, busy], provider: .codex, now: referenceNow)?
                .profileName == ".codex-work"
        )
    },
    TestCase(name: "Readout is empty when no provider drives the pet") {
        try require(MenuBarReadout.rows(
            snapshots: [snapshot(
                provider: .codex,
                profileName: ".codex",
                windows: [window("7日", 32, minutes: 10_080)]
            )],
            enabled: [],
            now: referenceNow
        ).isEmpty, "CPU mode passes no enabled providers and must draw nothing")
    },
    TestCase(name: "Window slots prefer known durations and never reuse one window") {
        let spend = window("支出上限", 62, minutes: nil)
        let five = window("5時間", 23, minutes: 300)
        let seven = window("7日", 41, minutes: 10_080)

        let three = MenuBarReadout.slots([seven, spend, five])
        try require(three.short?.label == "5時間", "got \(three.short?.label ?? "nil")")
        try require(three.long?.label == "7日", "got \(three.long?.label ?? "nil")")

        let onlyUnknown = MenuBarReadout.slots([spend])
        try require(onlyUnknown.short?.label == "支出上限")
        try require(onlyUnknown.long == nil, "one window must never fill both slots")

        try require(MenuBarReadout.slots([]).short == nil)
    },
    TestCase(name: "Tooltip lists every profile, window and reset time") {
        let claude = snapshot(
            provider: .claudeCode,
            profileName: ".claude-work",
            windows: [window("5時間", 23, minutes: 300)]
        )
        let codex = snapshot(
            provider: .codex,
            profileName: ".codex-work",
            windows: [],
            note: "クレジット切れ（workspace_member_credits_depleted）",
            reachedType: "workspace_member_credits_depleted"
        )
        let tooltip = MenuBarReadout.tooltip(
            snapshots: [claude, codex],
            enabled: Set(AIUsageProvider.allCases),
            now: referenceNow
        )
        try require(tooltip.contains("Claude Code（.claude-work）"), tooltip)
        try require(tooltip.contains("5時間 23%"), tooltip)
        try require(tooltip.contains("リセット"), tooltip)
        try require(tooltip.contains("枠の情報なし"), tooltip)
        try require(tooltip.contains("クレジット切れ"), tooltip)

        let nothing = MenuBarReadout.tooltip(
            snapshots: [],
            enabled: [.claudeCode],
            now: referenceNow
        )
        try require(nothing == "Claude Code: データなし", nothing)
    },
    TestCase(name: "Readout depends only on snapshots, providers and time") {
        // 一時停止などアプリ側の状態を引数に取らない＝「止まっているから数値も消える」を型で防ぐ。
        // 実機で一時停止中に数値が消えた（2026-09-16）のは、呼び出し側が読み取りを止めていたため。
        let live = snapshot(
            provider: .codex,
            profileName: ".codex-work",
            windows: [window("5時間", 17, minutes: 300), window("7日", 88, minutes: 10_080)]
        )
        for enabled in [Set(AIUsageProvider.allCases), [.codex], [.claudeCode]] as [Set<AIUsageProvider>] {
            let rows = MenuBarReadout.rows(snapshots: [live], enabled: enabled, now: referenceNow)
            try require(
                rows.count == enabled.count,
                "every enabled provider always gets a line: \(rows)"
            )
            try require(
                rows == MenuBarReadout.rows(snapshots: [live], enabled: enabled, now: referenceNow),
                "the same inputs must give the same rows"
            )
        }
    },
    TestCase(name: "Menu bar layout keeps both baselines inside twenty two points") {
        let layout = MenuBarReadout.Layout.self
        try require(layout.baselines(rowCount: 0).isEmpty)
        try require(layout.baselines(rowCount: 1) == [layout.singleBaseline])
        try require(layout.baselines(rowCount: 2) == [layout.topBaseline, layout.bottomBaseline])
        try require(layout.baselines(rowCount: 5) == [layout.topBaseline, layout.bottomBaseline])

        // 9pt の cap height ≈ 6.4pt、descender ≈ -2.1pt。
        // 上端は 1pt 以上あける（ここが切れたのが今回の不具合）。下端は描画がはみ出さないこと。
        let capHeight = 6.4
        let descender = 2.1
        for baseline in layout.baselines(rowCount: 2) + layout.baselines(rowCount: 1) {
            try require(baseline - descender > 0, "baseline \(baseline) sinks below the image")
            try require(
                baseline + capHeight <= layout.height - 1,
                "baseline \(baseline) pushes glyph tops out of the \(layout.height)pt strip"
            )
        }
        // 2 行が重ならない（上段の descender と下段の cap top が衝突しない）。
        try require(
            layout.topBaseline - descender >= layout.bottomBaseline + capHeight,
            "the two rows overlap"
        )
    },
    TestCase(name: "Menu bar width falls back to the plain forty four points") {
        let layout = MenuBarReadout.Layout.self
        try require(layout.width(textWidth: 60, rowCount: 0) == 44, "no rows means pet only")
        try require(
            layout.width(textWidth: 60, rowCount: 2) == 44 + 6 + 60 + 4,
            "got \(layout.width(textWidth: 60, rowCount: 2))"
        )
        // 端数は切り上げる（半端な幅でメニューバーが 1px ずれない）。
        try require(layout.width(textWidth: 59.2, rowCount: 2) == 44 + 6 + 60 + 4)
        try require(layout.width(textWidth: -5, rowCount: 1) == 44 + 6 + 4, "negative widths clamp")
        try require(layout.textOriginX() == 50)
    },
    TestCase(name: "Window slots stay in the given order when durations tie") {
        let first = AIUsageWindow(label: "A", usedPercentage: 1, resetsAt: nil, durationMinutes: 300)
        let second = AIUsageWindow(label: "B", usedPercentage: 2, resetsAt: nil, durationMinutes: 300)
        let slots = MenuBarReadout.slots([first, second])
        try require(slots.short?.label == "A", "got \(slots.short?.label ?? "nil")")
        try require(slots.long?.label == "B", "got \(slots.long?.label ?? "nil")")

        let reversed = MenuBarReadout.slots([second, first])
        try require(reversed.short?.label == "B", "order must follow the input, not the label")
    },
    TestCase(name: "Old settings JSON defaults the menu bar readout to on") {
        let legacy = Data("{\"metricSource\":\"aiUsage\"}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: legacy)
        try require(settings.showsMenuBarReadout, "the readout is on unless it was turned off")

        let saved = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(AppSettings(showsMenuBarReadout: false))
        )
        try require(!saved.showsMenuBarReadout, "turning it off must survive a round trip")
    },
]
