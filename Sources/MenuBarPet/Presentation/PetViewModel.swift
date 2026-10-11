import Combine
import Foundation
import MenuBarPetCore

@MainActor
final class PetViewModel: ObservableObject {
    /// キャラを動かす値（0〜100）。`.cpu` なら CPU 使用率、`.aiUsage` なら AI 使用枠の最大使用率。
    /// 名前は歴史的経緯で cpuUsage のまま（StatusItemController／PetMotion から見れば意味は同じ「駆動値」）。
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var state: PetState = .normal
    @Published var isPaused: Bool
    @Published var character: PetCharacter
    @Published var debugOverrideUsage: Double? = nil
    @Published private(set) var customFrameURLs: [URL] = []
    @Published var statusMessage: String?
    @Published private(set) var metricSource: MetricSource
    @Published private(set) var aiUsageProviders: Set<AIUsageProvider>
    @Published private(set) var showsMenuBarReadout: Bool

    /// CPU は細かい上下を見せたいので敏感、AI 残量は 75% 汗・90% 炎の意味を持たせたいので標準。
    var sensitivity: Sensitivity {
        metricSource == .cpu ? .sensitive : .standard
    }

    private let cpuSampler: CPUSampling
    private let settingsStore: SettingsStoring
    private let customRunnerStore: CustomRunnerStore
    private let aiUsage: AIUsageProviding?
    private var machine = PetStateMachine()
    private var sampleTimer: Timer?
    private var isPopoverVisible = false
    private var presentationCache = MenuBarPresentationCache()

    private var menuBarPresentation: MenuBarPresentation {
        presentationCache.presentation(
            snapshots: aiUsage?.snapshots ?? [], enabled: aiUsageProviders, now: Date()
        )
    }

    init(
        cpuSampler: CPUSampling,
        settingsStore: SettingsStoring,
        customRunnerStore: CustomRunnerStore = .applicationSupportStore(),
        aiUsage: AIUsageProviding? = nil
    ) {
        self.cpuSampler = cpuSampler
        self.settingsStore = settingsStore
        self.customRunnerStore = customRunnerStore
        self.aiUsage = aiUsage
        let settings = settingsStore.load()
        let frameURLs = customRunnerStore.loadFrameURLs()
        isPaused = settings.isPaused
        customFrameURLs = frameURLs
        character = settings.character == .custom && frameURLs.count < 2
            ? .shibaInu
            : settings.character
        metricSource = settings.metricSource
        aiUsageProviders = settings.aiUsageProviders
        showsMenuBarReadout = settings.showsMenuBarReadout
    }

    var availableCharacters: [PetCharacter] {
        customFrameURLs.count >= 2
            ? [.shibaInu, .hamsterWheel, .custom]
            : [.shibaInu, .hamsterWheel]
    }

    var accessibilitySummary: String {
        let metric = metricSource == .cpu ? "CPU" : "AI残量"
        // 一時停止で止まるのはアニメと状態機械だけ。数値は止めない（下の menuBarRows と同じ理由）。
        var summary = isPaused
            ? "メニューバーペット、一時停止中"
            : "メニューバーペット、\(state.displayName)、\(metric) \(Int(cpuUsage.rounded()))パーセント"
        // 画面に出しているのと同じ4数字を読み上げる。表示を切っているときは読ませない。
        for row in menuBarRows {
            summary += "、\(row.split(separator: " ").joined(separator: " "))"
        }
        return summary
    }

    /// メニューバーに出す2行。CPU モードと設定オフのときだけ空。
    ///
    /// **一時停止には連動させない。** 一時停止は「キャラが動くのがうるさい」ときの操作であって、
    /// 残量を見たくないという意思表示ではない。この機能の要件は「クリックせず即見れる」なので、
    /// 止まるのはアニメーションと状態機械だけにする（2026-09-16 実機で数値が消えた原因）。
    var menuBarRows: [String] {
        guard metricSource == .aiUsage, showsMenuBarReadout else { return [] }
        return menuBarPresentation.rows
    }

    var menuBarTooltip: String? {
        guard metricSource == .aiUsage else { return nil }
        let text = menuBarPresentation.tooltip
        return text.isEmpty ? nil : text
    }

    /// 見出しに出す「AI残量 88%（Codex 7日）」の材料。
    var aiBindingWindow: (snapshot: AIUsageSnapshot, window: AIUsageWindow)? {
        AIUsageAggregator.bindingWindow(
            snapshots: aiUsage?.snapshots ?? [],
            enabled: aiUsageProviders,
            now: Date()
        )
    }

    func start() {
        updateUsageActivity()
        guard !isPaused else {
            return
        }
        cpuSampler.reset()
        sampleTimer?.invalidate()
        sampleTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(sampleCPU),
            userInfo: nil,
            repeats: true
        )
        sampleTimer?.tolerance = 0.15
        sampleCPU()
    }

    func togglePaused() {
        isPaused.toggle()
        saveSettings()
        if isPaused {
            sampleTimer?.invalidate()
            sampleTimer = nil
            updateUsageActivity()
        } else {
            start()
        }
    }

    func setMetricSource(_ newValue: MetricSource) {
        guard newValue != metricSource else { return }
        metricSource = newValue
        // 指標が変わると意味する数値が変わるので、前の指標の平滑化を引きずらせない。
        machine.reset()
        state = .normal
        // CPU サンプラーは前回読み取りとの差分で使用率を出す。AI を見ていた間の古い基準が残っていると、
        // 戻った直後の1回が「その間ずっと動いていた」ぶんの巨大な値になる。
        if newValue == .cpu { cpuSampler.reset() }
        saveSettings()
        updateUsageActivity()
        aiUsage?.refresh()
        resample()
    }

    /// 最後の1つはオフにできない（全部オフ＝動かす値が無くなるため）。UI 側では Toggle を無効化し、
    /// ここは「無効化をすり抜けた場合に黙って無視する」ための最後の砦として残す。
    func setProvider(_ provider: AIUsageProvider, enabled: Bool) {
        var updated = aiUsageProviders
        if enabled {
            updated.insert(provider)
        } else {
            guard canDisableProvider(provider) else { return }
            updated.remove(provider)
        }
        guard updated != aiUsageProviders else { return }
        aiUsageProviders = updated
        saveSettings()
        resample()
    }

    /// そのプロバイダをオフにできるか（最後の1つなら不可）。
    func canDisableProvider(_ provider: AIUsageProvider) -> Bool {
        !(aiUsageProviders.count <= 1 && aiUsageProviders.contains(provider))
    }

    func setShowsMenuBarReadout(_ newValue: Bool) {
        guard newValue != showsMenuBarReadout else { return }
        showsMenuBarReadout = newValue
        saveSettings()
    }

    func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
        updateUsageActivity()
    }

    /// 設定を変えた直後に見出しを追いつかせる。一時停止中は凍らせたままにする。
    private func resample() {
        guard !isPaused else { return }
        sampleCPU()
    }

    /// 読み取りを回す条件。**一時停止は条件に入れない**——止めるとメニューバーの数値が
    /// 更新されなくなり、そのうち空になる。ディスクを読むだけなので一時停止中も 15 秒間隔で続ける。
    private func updateUsageActivity() {
        aiUsage?.setActive(isPopoverVisible || metricSource == .aiUsage)
    }

    func setCharacter(_ newValue: PetCharacter) {
        guard availableCharacters.contains(newValue) else { return }
        character = newValue
        saveSettings()
    }

    func registerCustomRunner(from urls: [URL]) {
        guard urls.count >= 2 else {
            statusMessage = "自作ランナーには2枚以上必要です。"
            return
        }
        guard urls.count <= 24 else {
            statusMessage = "自作ランナーは24枚まで登録できます。"
            return
        }
        do {
            customFrameURLs = try customRunnerStore.saveFrames(from: urls)
            character = .custom
            statusMessage = "自作ランナーを\(customFrameURLs.count)枚で登録しました。"
            saveSettings()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteCustomRunner() {
        do {
            try customRunnerStore.deleteAll()
            customFrameURLs = []
            if character == .custom { character = .shibaInu }
            statusMessage = "自作ランナーを削除しました。"
            saveSettings()
        } catch {
            statusMessage = "自作ランナーを削除できませんでした。"
        }
    }

    func handleWake() {
        machine.reset()
        state = .normal
        if !isPaused { start() }
    }

    @objc private func sampleCPU() {
        let sampledUsage: Double? = switch metricSource {
        case .cpu:
            cpuSampler.readUsage()
        case .aiUsage:
            // データがまだ無いのは異常ではなく初回状態なので、休息（0%）として流す。
            AIUsageAggregator.driveValue(
                snapshots: aiUsage?.snapshots ?? [],
                enabled: aiUsageProviders,
                now: Date()
            ) ?? 0
        }
        guard let usage = debugOverrideUsage ?? sampledUsage else { return }
        let snapshot = machine.ingest(usage, sensitivity: sensitivity)
        if cpuUsage != snapshot.smoothedUsage { cpuUsage = snapshot.smoothedUsage }
        if state != snapshot.state { state = snapshot.state }
    }

    private func saveSettings() {
        settingsStore.save(AppSettings(
            isPaused: isPaused,
            character: character,
            metricSource: metricSource,
            aiUsageProviders: aiUsageProviders,
            showsMenuBarReadout: showsMenuBarReadout
        ))
    }
}
