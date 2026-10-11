import Combine
import Foundation
import MenuBarPetCore

/// Claude Code と Codex の使用枠をディスクから拾い集める。
///
/// 常駐負荷を増やさないため、AI モード中か popover 表示中だけ 15 秒ごとに回す。
/// それ以外はタイマーごと止める（RunCat 系の常駐アプリで一番嫌われるのが「何もしていない時のCPU」なので）。
@MainActor
final class AIUsageRepository: ObservableObject, AIUsageProviding {
    static let refreshInterval: TimeInterval = 15

    @Published private(set) var snapshots: [AIUsageSnapshot] = []
    @Published private(set) var lastRefreshedAt: Date?

    private let homeDirectory: URL
    private let store: AIUsageStore
    private let loader: AIUsageLoader
    private var refreshTask: Task<Void, Never>?
    private var timer: Timer?
    private var isActive = false

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        store: AIUsageStore = .make()
    ) {
        self.homeDirectory = homeDirectory
        self.store = store
        self.loader = AIUsageLoader(homeDirectory: homeDirectory, store: store)
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            refresh()
            let timer = Timer(
                timeInterval: Self.refreshInterval,
                target: self,
                selector: #selector(refreshFromTimer),
                userInfo: nil,
                repeats: true
            )
            timer.tolerance = Self.refreshInterval * 0.2
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    @objc private func refreshFromTimer() {
        refresh()
    }

    func refresh() {
        guard refreshTask == nil else { return }
        let loader = self.loader
        refreshTask = Task { [weak self] in
            let loaded = await loader.load()
            guard let self else { return }
            if snapshots != loaded { snapshots = loaded }
            lastRefreshedAt = Date()
            refreshTask = nil
        }
    }
}

/// Serial disk work stays on this actor's executor instead of blocking the menu bar.
private actor AIUsageLoader {
    let homeDirectory: URL
    let store: AIUsageStore
    var scanner = CodexSessionScanner()

    init(homeDirectory: URL, store: AIUsageStore) {
        self.homeDirectory = homeDirectory
        self.store = store
    }

    func load() -> [AIUsageSnapshot] {
        store.readClaudeSnapshots() + scanner.snapshots(homeDirectory: homeDirectory)
    }
}
