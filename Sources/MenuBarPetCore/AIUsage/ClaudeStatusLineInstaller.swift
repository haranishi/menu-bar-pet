import Foundation

public enum ClaudeSettingsFileError: Error, Equatable {
    /// ファイルはあるのに読めない（権限・I/Oエラー）。中身が分からない以上、書き換えてはいけない。
    case unreadable(String)
}

/// `~/.claude*/settings.json` の `statusLine` を本アプリに向ける／戻す純関数。
///
/// 既に別の statusLine がある人の表示を壊さないため、上書きではなく
/// `<本アプリ> --statusline --then '<元のcommand>'` に連結する。元のコマンドは settings.json に
/// 文字列として残るので、アプリを消しても人手で復元できる。
///
/// 当アプリのコマンドかどうかは **絶対パスではなく実行体名 + `--statusline`** で判定する。
/// アプリを移動した後に自分自身をもう一段ラップしてしまい、解除しても元へ戻らなくなるのを防ぐため。
public enum ClaudeStatusLineInstaller {
    private static let statusLineKey = "statusLine"
    private static let commandKey = "command"
    private static let thenFlag = "--then"
    private static let statusLineFlag = "--statusline"
    private static let executableName = "MenuBarPet"

    /// 本アプリの statusLine コマンド。パスに空白が入りうるのでクォートする。
    public static func command(forBinaryPath binaryPath: String) -> String {
        "\"\(binaryPath)\" \(statusLineFlag)"
    }

    /// 実行体名と `--statusline` で「当アプリのコマンド」を見分ける（パスが変わっても効く）。
    public static func isOurCommand(_ command: String) -> Bool {
        guard let range = command.range(of: " \(statusLineFlag)") else { return false }
        let head = String(command[command.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let unquoted = head.hasPrefix("\"") && head.hasSuffix("\"") && head.count >= 2
            ? String(head.dropFirst().dropLast())
            : head
        guard !unquoted.isEmpty else { return false }
        return URL(fileURLWithPath: unquoted).lastPathComponent == executableName
    }

    public static func installedCommand(settingsData: Data?) -> String? {
        guard let root = object(from: settingsData),
              let command = currentCommand(root: root),
              isOurCommand(command)
        else { return nil }
        return command
    }

    public static func isInstalled(settingsData: Data?) -> Bool {
        installedCommand(settingsData: settingsData) != nil
    }

    /// 既存の statusLine を引き継いだうえで本アプリに向ける。
    ///
    /// `settingsData` が nil は「ファイルがまだ無い＝新規作成」の意味。**読めなかった**場合に nil を
    /// 渡してはいけない（既存の設定を丸ごと捨てることになる）。呼び出し側は `readSettings` を使う。
    /// 既に当アプリのコマンドが入っていれば、内側の `--then` を1段ほどいてから新しいパスで組み直す。
    public static func install(settingsData: Data?, command ourCommand: String) -> Data {
        guard var root = object(from: settingsData) else {
            return settingsData ?? Data()
        }
        var statusLine = existingStatusLineObject(root: root)
        let existing = AIUsageJSON.string(statusLine[commandKey])

        // 当アプリのコマンドなら最内の元コマンドまでほどく（多重ラップを作らない）。
        let inherited = existing.flatMap { isOurCommand($0) ? innermostCommand(in: $0) : $0 }
        let newCommand = inherited.map { "\(ourCommand) \(thenFlag) \(singleQuoted($0))" } ?? ourCommand
        if newCommand == existing { return settingsData ?? Data() }

        statusLine["type"] = "command"
        statusLine[commandKey] = newCommand
        root[statusLineKey] = statusLine
        return serialize(root) ?? settingsData ?? Data()
    }

    /// 本アプリの statusLine を外す。`--then` があれば最内の元コマンドへ戻し、無ければキーごと消す。
    public static func uninstall(settingsData: Data) -> Data {
        guard var root = object(from: settingsData) else { return settingsData }
        var statusLine = existingStatusLineObject(root: root)
        guard let command = AIUsageJSON.string(statusLine[commandKey]), isOurCommand(command) else {
            return settingsData
        }

        if let original = innermostCommand(in: command) {
            statusLine["type"] = "command"
            statusLine[commandKey] = original
            root[statusLineKey] = statusLine
        } else {
            root.removeValue(forKey: statusLineKey)
        }
        return serialize(root) ?? settingsData
    }

    /// 本アプリのコマンドに包まれた、1段内側のコマンド。
    public static func wrappedCommand(in command: String) -> String? {
        guard let range = command.range(of: " \(thenFlag) ") else { return nil }
        return singleQuotedValue(String(command[range.upperBound...]))
    }

    /// 何段ラップされていても、最後に残る「人のコマンド」を取り出す。
    public static func innermostCommand(in command: String) -> String? {
        var current = wrappedCommand(in: command)
        while let value = current, isOurCommand(value), let inner = wrappedCommand(in: value) {
            current = inner
        }
        // 当アプリのコマンドだけが残ったなら、人のコマンドは無い。
        if let value = current, isOurCommand(value) { return nil }
        return current
    }

    /// settings.json を読む。ファイルが無ければ nil、あるのに読めなければ throw。
    public static func readSettings(
        at url: URL,
        fileManager: FileManager = .default
    ) throws -> Data? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ClaudeSettingsFileError.unreadable(url.lastPathComponent)
        }
    }

    // MARK: - シェル引数のクォート

    /// `/bin/sh -c` に渡す前提のシングルクォート。内部の `'` は `'\''` で閉じ直す定石。
    public static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func singleQuotedValue(_ quoted: String) -> String? {
        let trimmed = quoted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.hasPrefix("'"), trimmed.hasSuffix("'") else {
            return trimmed.isEmpty ? nil : trimmed
        }
        let inner = String(trimmed.dropFirst().dropLast())
        return inner.replacingOccurrences(of: "'\\''", with: "'")
    }

    // MARK: - JSON

    private static func object(from data: Data?) -> [String: Any]? {
        guard let data else { return [:] }
        if data.isEmpty { return [:] }
        return AIUsageJSON.object(try? JSONSerialization.jsonObject(with: data))
    }

    /// `statusLine` は本来オブジェクトだが、コマンド文字列だけを書いている人がいる。
    /// 文字列で書かれていても「元のコマンド」として扱えるよう、オブジェクトに正規化する。
    private static func existingStatusLineObject(root: [String: Any]) -> [String: Any] {
        if let object = AIUsageJSON.object(root[statusLineKey]) { return object }
        if let command = AIUsageJSON.string(root[statusLineKey]) {
            return ["type": "command", commandKey: command]
        }
        return [:]
    }

    private static func currentCommand(root: [String: Any]) -> String? {
        AIUsageJSON.string(existingStatusLineObject(root: root)[commandKey])
    }

    private static func serialize(_ root: [String: Any]) -> Data? {
        guard var data = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return nil }
        data.append(0x0A)
        return data
    }
}
