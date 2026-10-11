import Foundation

/// Parses only usage events from the supplied local log tail in Rust.
public enum CodexSessionParser {
    public static func parseLatest(
        text: String, observedAtFallback: Date, profileName: String, sourcePath: String
    ) -> AIUsageSnapshot? {
        RustUsageBridge.parse(
            Data(text.utf8), provider: .codex, observedAt: observedAtFallback,
            profileName: profileName, sourcePath: sourcePath
        )
    }
    public static func windowLabel(minutes: Double) -> String {
        guard minutes.isFinite, minutes > 0 else { return "枠" }
        if minutes < 60 { return "\(trimmed(minutes))分" }
        if minutes < 1_440 { return "\(trimmed(minutes / 60))時間" }
        return "\(trimmed(minutes / 1_440))日"
    }

    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 1e-9 { return "\(Int(rounded.rounded()))" }
        return String(format: "%.1f", rounded)
    }

}

struct ISO8601TimestampParser {
    private let withFraction: ISO8601DateFormatter
    private let withoutFraction: ISO8601DateFormatter

    init() {
        withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
    }

    func date(from text: String?) -> Date? {
        guard let text else { return nil }
        return withFraction.date(from: text) ?? withoutFraction.date(from: text)
    }

    func string(from date: Date) -> String {
        withFraction.string(from: date)
    }
}
