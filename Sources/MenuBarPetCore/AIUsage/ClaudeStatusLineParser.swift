import Foundation

/// Parses local statusLine input in the Rust core; no credentials or network access.
public enum ClaudeStatusLineParser {
    public static func parse(
        _ data: Data, observedAt: Date, profileName: String, sourcePath: String
    ) -> AIUsageSnapshot? {
        RustUsageBridge.parse(
            data, provider: .claudeCode, observedAt: observedAt,
            profileName: profileName, sourcePath: sourcePath
        )
    }
}
