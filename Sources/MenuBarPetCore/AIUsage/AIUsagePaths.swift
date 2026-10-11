import Foundation

public enum AIUsageConfigKind: Sendable {
    case claude
    case codex

    /// 設定ホームの接頭辞。`~/.claude` `~/.claude-work` のように、素の名前と `-` 付きの派生を拾う。
    var directoryPrefix: String {
        switch self {
        case .claude: ".claude"
        case .codex: ".codex"
        }
    }

    /// そのディレクトリが本物の設定ホームかを決める目印。
    var requiredChild: String {
        switch self {
        case .claude: "settings.json"
        case .codex: "sessions"
        }
    }
}

public struct AIUsageConfigDirectory: Equatable, Sendable {
    public let url: URL
    /// basename。例 ".claude-work"
    public let profileName: String

    public init(url: URL, profileName: String) {
        self.url = url
        self.profileName = profileName
    }
}

/// 置き場所の規約。バンドルIDに依存させない（CLI モードでは Bundle が当てにならないため）。
public enum AIUsagePaths {
    public static let usageDirectoryEnvironmentKey = "MENUBARPET_USAGE_DIR"
    public static let defaultClaudeProfileName = ".claude"
    private static let claudeConfigDirEnvironmentKey = "CLAUDE_CONFIG_DIR"

    public static func usageDirectory(
        homeDirectory: URL,
        environment: [String: String]
    ) -> URL {
        if let override = environment[usageDirectoryEnvironmentKey], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }
        return homeDirectory
            .appendingPathComponent("Library/Application Support/MenuBarPet/AIUsage", isDirectory: true)
            .standardizedFileURL
    }

    public static func claudeUsageFileURL(directory: URL, profileName: String) -> URL {
        directory.appendingPathComponent("claude-\(profileName).json", isDirectory: false)
    }

    /// ファイル名 `claude-<profile>.json` から profile を戻す。
    public static func claudeProfileName(fromFileName fileName: String) -> String? {
        guard fileName.hasPrefix("claude-"), fileName.hasSuffix(".json") else { return nil }
        let profile = String(fileName.dropFirst("claude-".count).dropLast(".json".count))
        return profile.isEmpty ? nil : profile
    }

    /// statusLine を動かしている Claude Code が、どの設定ホームのものかを環境変数から決める。
    public static func claudeProfileName(
        environment: [String: String],
        homeDirectory: URL
    ) -> String {
        let path = environment[claudeConfigDirEnvironmentKey].flatMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let path else { return defaultClaudeProfileName }
        let name = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.lastPathComponent
        return name.isEmpty || name == "/" ? defaultClaudeProfileName : name
    }

    /// `~` 直下から設定ホームを拾う。`~/.claude.json` のような **ファイル** は除外する。
    public static func discoverConfigDirectories(
        _ kind: AIUsageConfigKind,
        in homeDirectory: URL,
        using fileManager: FileManager
    ) -> [AIUsageConfigDirectory] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: homeDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }

        let prefix = kind.directoryPrefix
        return contents
            .compactMap { url -> AIUsageConfigDirectory? in
                let name = url.lastPathComponent
                guard name == prefix || name.hasPrefix("\(prefix)-") else { return nil }
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      isDirectory.boolValue
                else { return nil }
                let child = url.appendingPathComponent(kind.requiredChild)
                guard fileManager.fileExists(atPath: child.path) else { return nil }
                return AIUsageConfigDirectory(url: url.standardizedFileURL, profileName: name)
            }
            .sorted { $0.profileName < $1.profileName }
    }
}

/// statusLine が書いた JSON を置く小さなファイル置き場。
public struct AIUsageStore: Sendable {
    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL.standardizedFileURL
    }

    public static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> AIUsageStore {
        AIUsageStore(directoryURL: AIUsagePaths.usageDirectory(
            homeDirectory: homeDirectory,
            environment: environment
        ))
    }

    public func write(_ data: Data, profileName: String) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let url = AIUsagePaths.claudeUsageFileURL(directory: directoryURL, profileName: profileName)
        try data.write(to: url, options: .atomic)
    }

    /// 置いてある `claude-*.json` を全部読む。壊れたファイルは黙って飛ばす。
    public func readClaudeSnapshots(using fileManager: FileManager = .default) -> [AIUsageSnapshot] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .compactMap { url -> AIUsageSnapshot? in
                guard let profile = AIUsagePaths.claudeProfileName(fromFileName: url.lastPathComponent),
                      let data = try? Data(contentsOf: url)
                else { return nil }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? Date()
                return ClaudeStatusLineParser.parse(
                    data,
                    observedAt: modified,
                    profileName: profile,
                    sourcePath: url.path
                )
            }
            .sorted { $0.profileName < $1.profileName }
    }
}
