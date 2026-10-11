import AppKit
import Combine
import MenuBarPetCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let model: PetViewModel
    private let aiUsage: AIUsageRepository
    private let systemMonitor = SystemMonitor()
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let imageView = StatusImageView()
    private var imageSize: NSSize?
    private let popoverVisibility = PopoverVisibility()
    private let popoverPresentation = PopoverPresentation()
    private var cancellables = Set<AnyCancellable>()
    private var frameTimer: Timer?
    private var configuredFramesPerSecond: Double?
    private var motionClock = PetMotionClock()
    private var wheelClock = HamsterWheelClock()
    private var lastFrameTime: TimeInterval?
    private var accessibilityObserver: NSObjectProtocol?
    private var customFrames: [NSImage] = []
    private var lastTooltip: String?
    private var lastAccessibilityLabel: String?

    init(model: PetViewModel, aiUsage: AIUsageRepository) {
        self.model = model
        self.aiUsage = aiUsage
        // 幅は合成画像まかせ（variableLength）。数値で length を代入してはいけない——
        // macOS 26 のノッチ付き本体ディスプレイでは length の変更がホスト窓に反映されず、
        // 項目の右側（数値）が黒くマスクされて見えなくなった（2026-09-16 実機。外部ディスプレイは正常）。
        // variableLength なら反映される。CPU モードは合成側が 44pt の画像を返すので従来どおり。
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configurePopover()
        observeModel()
        refreshStatusItem()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "メニューバーペット"
        button.setAccessibilityLabel("メニューバーペット")
        // 数字はボタンに描かせず、キャラと1枚の画像に合成してから渡す（上端が切れるため）。
        button.imagePosition = .imageOnly
        button.attributedTitle = NSAttributedString(string: "")
        imageView.frame = button.bounds
        imageView.autoresizingMask = [.width, .height]
        button.addSubview(imageView)
        imageView.onAppearanceChanged = { [weak self] in self?.refreshStatusItem() }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 560)
        popover.contentViewController = NSHostingController(rootView: PopoverMountGate(
            visibility: popoverVisibility,
            model: model,
            systemMonitor: systemMonitor,
            aiUsage: aiUsage,
            presentation: popoverPresentation,
            onVisualSettingsChanged: { [weak self] in self?.refreshStatusItem() },
            onQuit: { NSApplication.shared.terminate(nil) }
        ))
    }

    private func observeModel() {
        model.$state
            .combineLatest(model.$character, model.$isPaused)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.refreshStatusItem() }
            .store(in: &cancellables)
        model.$customFrameURLs
            .receive(on: RunLoop.main)
            .sink { [weak self] urls in
                guard let self else { return }
                self.customFrames = urls.compactMap { NSImage(contentsOf: $0) }
                self.refreshStatusItem()
            }
            .store(in: &cancellables)
        model.$cpuUsage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.statusItem.button?.setAccessibilityLabel(self.model.accessibilitySummary)
                self.configureFrameTimer(reduceMotion: self.shouldReduceMotion)
            }
            .store(in: &cancellables)
        // 数値表示は「読み取りが更新されたとき」と「設定が変わったとき」に描き直す。
        aiUsage.$lastRefreshedAt
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshReadout() }
            .store(in: &cancellables)
        model.$metricSource
            .combineLatest(model.$showsMenuBarReadout, model.$aiUsageProviders)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.refreshReadout() }
            .store(in: &cancellables)

        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshStatusItem() }
        }
    }

    func refreshStatusItem() {
        let reduceMotion = shouldReduceMotion
        renderFrame(reduceMotion: reduceMotion)
        configureFrameTimer(reduceMotion: reduceMotion)
        refreshReadout()
    }

    /// 数字が変わったら描き直す。合成方式なので、貼り替えるのは画像1枚だけ。
    private func refreshReadout() {
        renderFrame(reduceMotion: shouldReduceMotion)
    }

    private var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || model.isPaused
    }

    private var animationFrameCount: Int {
        model.character == .custom && !customFrames.isEmpty ? customFrames.count : (model.state == .resting ? 12 : 48)
    }

    private func configureFrameTimer(reduceMotion: Bool) {
        guard !reduceMotion else {
            frameTimer?.invalidate()
            frameTimer = nil
            configuredFramesPerSecond = nil
            lastFrameTime = nil
            return
        }

        let framesPerSecond = PetMotion.framesPerSecond(
            state: model.state,
            cpu: model.cpuUsage,
            frameCount: animationFrameCount
        )
        if let configuredFramesPerSecond,
           frameTimer != nil,
           abs(framesPerSecond - configuredFramesPerSecond) / configuredFramesPerSecond < 0.10 {
            return
        }

        frameTimer?.invalidate()
        let interval = 1 / framesPerSecond
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(drawNextFrame),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = interval * 0.15
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
        configuredFramesPerSecond = framesPerSecond
        if lastFrameTime == nil {
            lastFrameTime = ProcessInfo.processInfo.systemUptime
        }
    }

    @objc private func drawNextFrame() {
        guard !shouldReduceMotion else {
            refreshStatusItem()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = lastFrameTime.map { max(0, now - $0) } ?? 0
        lastFrameTime = now
        motionClock.advance(elapsed: elapsed, cpu: model.cpuUsage)
        wheelClock.advance(elapsed: elapsed, cpu: model.cpuUsage)
        renderFrame(reduceMotion: false)
    }

    private func renderFrame(reduceMotion: Bool) {
        guard let button = statusItem.button else { return }
        let isDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let pet = PetRenderer.render(
            character: model.character,
            state: model.state,
            phase: motionClock.phase,
            wheelPhase: wheelClock.phase,
            isDarkAppearance: isDark,
            reduceMotion: reduceMotion,
            customFrames: customFrames
        )
        let rows = model.menuBarRows
        let image = MenuBarComposer.compose(pet: pet, rows: rows, isDark: isDark)
        // Setting NSStatusBarButton.image on every tick also recalculates the menu-bar window.
        // Keep image-driven variableLength sizing, then update only the drawing layer.
        if imageSize != image.size {
            imageSize = image.size
            let sizingImage = NSImage(size: image.size)
            sizingImage.isTemplate = false
            button.image = sizingImage
        }
        imageView.display(image)
        let tooltip = rows.isEmpty
            ? "メニューバーペット"
            : (model.menuBarTooltip ?? "メニューバーペット")
        if tooltip != lastTooltip {
            button.toolTip = tooltip
            lastTooltip = tooltip
        }
        let summary = model.accessibilitySummary
        if summary != lastAccessibilityLabel {
            button.setAccessibilityLabel(summary)
            lastAccessibilityLabel = summary
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popoverVisibility.isVisible = true
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

// システム情報とAI残量のサンプリングはpopoverが開いている間だけ動かす（常駐負荷を増やさないため）。
// AI残量は「動かす指標」に選ばれている間も回り続ける＝その判断はPetViewModelが持つ。
extension StatusItemController: NSPopoverDelegate {
    func popoverDidShow(_ notification: Notification) {
        systemMonitor.start()
        model.setPopoverVisible(true)
    }

    func popoverDidClose(_ notification: Notification) {
        popoverVisibility.isVisible = false
        systemMonitor.stop()
        model.setPopoverVisible(false)
    }
}
