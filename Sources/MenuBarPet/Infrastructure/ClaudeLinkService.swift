import Foundation
import MenuBarPetCore

struct ClaudeLinkTarget: Identifiable, Equatable {
    let profileName: String
    let settingsURL: URL
    let isInstalled: Bool
    /// 当アプリの statusLine だが、書いてあるパスが今の実行ファイルと違う（アプリを移動した後）。
    let needsRelink: Bool

    var id: String { profileName }

    var statusText: String {
        if needsRelink { return "設定済み（旧パス）" }
        return isInstalled ? "設定済み" : "未設定"
    }
}

enum ClaudeLinkError: LocalizedError {
    case unknownBinaryPath
    case unreadableSettings(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unknownBinaryPath:
            "アプリ本体の場所が分からないため連携できません。"
        case let .unreadableSettings(profile):
            "\(profile) の settings.json を読めませんでした。中身が分からないので書き換えません。"
        case let .writeFailed(message):
            "settings.json を書けませんでした: \(message)"
        }
    }
}

/// `~/.claude*/settings.json` の statusLine を本アプリに向ける／戻す。
///
/// 書き込むのは本人がボタンを押したときだけ。書き換える前に必ずタイムスタンプ付きの控えを残す
/// （statusLine は毎回の応答で走るので、壊すと Claude Code 側の画面が崩れるため）。
/// **ファイルがあるのに読めない場合は書かない**——読めないものを「無い」と同じ扱いにすると、
/// 既存の設定を丸ごと消してしかも控えも残らない。
@MainActor
enum ClaudeLinkService {
    static var binaryPath: String? {
        Bundle.main.executableURL?.resolvingSymlinksInPath().path
    }

    static func targets(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [ClaudeLinkTarget] {
        let expected = binaryPath.map(ClaudeStatusLineInstaller.command(forBinaryPath:))
        return AIUsagePaths
            .discoverConfigDirectories(.claude, in: homeDirectory, using: .default)
            .map { directory in
                let settingsURL = directory.url.appendingPathComponent("settings.json")
                let data = try? ClaudeStatusLineInstaller.readSettings(at: settingsURL)
                let installed = ClaudeStatusLineInstaller.installedCommand(settingsData: data ?? nil)
                return ClaudeLinkTarget(
                    profileName: directory.profileName,
                    settingsURL: settingsURL,
                    isInstalled: installed != nil,
                    needsRelink: installed.map { command in
                        expected.map { !command.hasPrefix($0) } ?? false
                    } ?? false
                )
            }
    }

    static func link(_ target: ClaudeLinkTarget) throws {
        guard let binaryPath else { throw ClaudeLinkError.unknownBinaryPath }
        let data = try readSettings(at: target.settingsURL, profileName: target.profileName)
        let updated = ClaudeStatusLineInstaller.install(
            settingsData: data,
            command: ClaudeStatusLineInstaller.command(forBinaryPath: binaryPath)
        )
        guard ClaudeStatusLineInstaller.isInstalled(settingsData: updated) else {
            throw ClaudeLinkError.unreadableSettings(target.profileName)
        }
        try write(updated, to: target.settingsURL, backingUp: data)
    }

    static func unlink(_ target: ClaudeLinkTarget) throws {
        guard let data = try readSettings(at: target.settingsURL, profileName: target.profileName) else {
            throw ClaudeLinkError.unreadableSettings(target.profileName)
        }
        let updated = ClaudeStatusLineInstaller.uninstall(settingsData: data)
        try write(updated, to: target.settingsURL, backingUp: data)
    }

    /// nil は「ファイルが無い＝新規作成してよい」。読めないときは throw する。
    private static func readSettings(at url: URL, profileName: String) throws -> Data? {
        do {
            return try ClaudeStatusLineInstaller.readSettings(at: url)
        } catch {
            throw ClaudeLinkError.unreadableSettings(profileName)
        }
    }

    static func backupFileName(for url: URL, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(url.lastPathComponent).menubarpet-backup-\(formatter.string(from: now))"
    }

    private static func write(_ data: Data, to url: URL, backingUp original: Data?) throws {
        do {
            if let original {
                let backupURL = url
                    .deletingLastPathComponent()
                    .appendingPathComponent(backupFileName(for: url, now: Date()))
                try original.write(to: backupURL, options: .atomic)
            }
            try data.write(to: url, options: .atomic)
        } catch {
            throw ClaudeLinkError.writeFailed(error.localizedDescription)
        }
    }
}
