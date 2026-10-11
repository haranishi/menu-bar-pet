import Foundation

/// 同じファイルを何度も読み直さないための指紋。
public struct CodexFileFingerprint: Equatable, Sendable {
    public let modified: Date
    public let size: Int

    public init(modified: Date, size: Int) {
        self.modified = modified
        self.size = size
    }
}

/// `~/.codex*/sessions` から最新のスナップショットを1プロファイル1つ選ぶ。
///
/// セッションログは1本が数十MBまで育つので、全文は読まずに末尾だけ見る。
/// 採用規則は **枠ありを優先し、同条件なら observedAt 最大**。上限到達で枠が消えた新しいセッションが、
/// 枠を持つ少し前のセッションを追い出して「使用率不明」になるのを防ぐ。
/// 走査幅は既定 2日×3本。枠が1つも見つからない間だけ 3日×16本まで伸ばす（普段はディスクを舐めない）。
/// 16本という数は実測から決めた——上限に当たった日は短命なセッションが十数本並び、
/// 枠を持つ最初のファイルが mtime 降順で14番目だった。6本では届かない。
public struct CodexSessionScanner: Sendable {
    public static let tailByteCount = 512 * 1_024
    public static let maxDaysScanned = 2
    public static let maxFilesScanned = 3
    public static let widenedDaysScanned = 3
    public static let widenedFilesScanned = 16

    private var cache: [String: (fingerprint: CodexFileFingerprint, snapshot: AIUsageSnapshot?)] = [:]

    public init() {}

    public mutating func snapshots(
        homeDirectory: URL,
        fileManager: FileManager = .default
    ) -> [AIUsageSnapshot] {
        let homes = AIUsagePaths.discoverConfigDirectories(
            .codex,
            in: homeDirectory,
            using: fileManager
        )
        var seenPaths: Set<String> = []
        var results: [AIUsageSnapshot] = []
        for home in homes {
            var parsed = read(
                home: home,
                fileManager: fileManager,
                maxDays: Self.maxDaysScanned,
                maxFiles: Self.maxFilesScanned,
                seenPaths: &seenPaths
            )
            // 枠がまだ1つも取れていないときだけ、範囲を広げてもう一度当たる。
            if !parsed.contains(where: { !$0.windows.isEmpty }) {
                parsed = read(
                    home: home,
                    fileManager: fileManager,
                    maxDays: Self.widenedDaysScanned,
                    maxFiles: Self.widenedFilesScanned,
                    seenPaths: &seenPaths
                )
            }
            if let snapshot = Self.adopt(parsed) { results.append(snapshot) }
        }
        // 触らなくなったファイルの指紋は落としておく（古いセッションを溜め込まない）。
        cache = cache.filter { seenPaths.contains($0.key) }
        return results.sorted { $0.profileName < $1.profileName }
    }

    private mutating func read(
        home: AIUsageConfigDirectory,
        fileManager: FileManager,
        maxDays: Int,
        maxFiles: Int,
        seenPaths: inout Set<String>
    ) -> [AIUsageSnapshot] {
        var parsed: [AIUsageSnapshot] = []
        for url in recentFiles(
            in: home.url,
            fileManager: fileManager,
            maxDays: maxDays,
            maxFiles: maxFiles
        ) {
            seenPaths.insert(url.path)
            if let snapshot = snapshot(at: url, profileName: home.profileName, fileManager: fileManager) {
                parsed.append(snapshot)
            }
        }
        return parsed
    }

    /// 枠ありを優先して1つ選び、上限到達の報せだけは最新のものを載せ替える。
    static func adopt(_ snapshots: [AIUsageSnapshot]) -> AIUsageSnapshot? {
        func noteTime(_ snapshot: AIUsageSnapshot) -> Date {
            snapshot.noteObservedAt ?? snapshot.observedAt
        }

        let withWindows = snapshots.filter { !$0.windows.isEmpty }
        guard let best = (withWindows.isEmpty ? snapshots : withWindows)
            .max(by: { $0.observedAt < $1.observedAt })
        else { return nil }

        guard let newestNote = snapshots
            .filter({ $0.rateLimitReachedType != nil })
            .max(by: { noteTime($0) < noteTime($1) }),
            noteTime(newestNote) > (best.noteObservedAt ?? .distantPast)
        else { return best }

        var extras = best.extras
        extras[AIUsageSnapshot.rateLimitReachedTypeKey] = newestNote.rateLimitReachedType
        extras[AIUsageSnapshot.noteObservedAtKey] = newestNote.extras[AIUsageSnapshot.noteObservedAtKey]
        return AIUsageSnapshot(
            provider: best.provider,
            profileName: best.profileName,
            windows: best.windows,
            observedAt: best.observedAt,
            note: newestNote.note,
            sourcePath: best.sourcePath,
            extras: extras
        )
    }

    private mutating func snapshot(
        at url: URL,
        profileName: String,
        fileManager: FileManager
    ) -> AIUsageSnapshot? {
        guard let fingerprint = fingerprint(of: url, fileManager: fileManager) else { return nil }
        if let cached = cache[url.path], cached.fingerprint == fingerprint {
            return cached.snapshot
        }
        let snapshot = Self.readTail(of: url, maxBytes: Self.tailByteCount).flatMap { text in
            CodexSessionParser.parseLatest(
                text: text,
                observedAtFallback: fingerprint.modified,
                profileName: profileName,
                sourcePath: url.path
            )
        }
        cache[url.path] = (fingerprint, snapshot)
        return snapshot
    }

    /// 日付ディレクトリ降順で最新 `maxDays` 日ぶん → mtime 降順で `maxFiles` 本。
    func recentFiles(
        in homeURL: URL,
        fileManager: FileManager,
        maxDays: Int = CodexSessionScanner.maxDaysScanned,
        maxFiles: Int = CodexSessionScanner.maxFilesScanned
    ) -> [URL] {
        let sessionsURL = homeURL.appendingPathComponent("sessions", isDirectory: true)
        let dayDirectories = Self.dayDirectories(
            in: sessionsURL,
            fileManager: fileManager,
            limit: maxDays
        )

        var candidates: [(url: URL, modified: Date)] = []
        for day in dayDirectories {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: day,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in contents where url.lastPathComponent.hasPrefix("rollout-")
                && url.pathExtension.lowercased() == "jsonl" {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                candidates.append((url, modified))
            }
        }
        return candidates
            .sorted {
                $0.modified == $1.modified
                    ? $0.url.lastPathComponent > $1.url.lastPathComponent
                    : $0.modified > $1.modified
            }
            .prefix(maxFiles)
            .map(\.url)
    }

    /// `sessions/YYYY/MM/DD` を新しい順に返す。
    static func dayDirectories(in sessionsURL: URL, fileManager: FileManager, limit: Int) -> [URL] {
        func numericChildren(of url: URL) -> [(value: Int, url: URL)] {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            return contents
                .compactMap { child -> (Int, URL)? in
                    guard let value = Int(child.lastPathComponent) else { return nil }
                    var isDirectory: ObjCBool = false
                    guard fileManager.fileExists(atPath: child.path, isDirectory: &isDirectory),
                          isDirectory.boolValue
                    else { return nil }
                    return (value, child)
                }
                .sorted { $0.0 > $1.0 }
        }

        var days: [URL] = []
        for year in numericChildren(of: sessionsURL) {
            for month in numericChildren(of: year.url) {
                days.append(contentsOf: numericChildren(of: month.url).map(\.url))
                if days.count >= limit { return Array(days.prefix(limit)) }
            }
        }
        return days
    }

    private func fingerprint(of url: URL, fileManager: FileManager) -> CodexFileFingerprint? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        let modified = attributes[.modificationDate] as? Date ?? .distantPast
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return CodexFileFingerprint(modified: modified, size: size)
    }

    /// 末尾だけを読む。UTF-8 の途中で切れた先頭バイトは捨てて復元する。
    public static func readTail(of url: URL, maxBytes: Int) -> String? {
        RustUsageBridge.readTail(of: url, maxBytes: maxBytes)
    }
}
