import Foundation

/// Usage values are sampled in seconds; animation frames reuse the same presentation.
public struct MenuBarPresentation: Equatable, Sendable {
    public let rows: [String]
    public let tooltip: String
}

public struct MenuBarPresentationCache: Sendable {
    private var snapshots: [AIUsageSnapshot] = []
    private var providers: Set<AIUsageProvider> = []
    private var second: Double?
    private var value = MenuBarPresentation(rows: [], tooltip: "")

    public init() {}

    public mutating func presentation(
        snapshots: [AIUsageSnapshot], enabled: Set<AIUsageProvider>, now: Date
    ) -> MenuBarPresentation {
        let currentSecond = floor(now.timeIntervalSince1970)
        if second != currentSecond || self.snapshots != snapshots || providers != enabled {
            self.snapshots = snapshots
            providers = enabled
            second = currentSecond
            value = MenuBarPresentation(
                rows: MenuBarReadout.rows(snapshots: snapshots, enabled: enabled, now: now),
                tooltip: MenuBarReadout.tooltip(snapshots: snapshots, enabled: enabled, now: now)
            )
        }
        return value
    }
}
