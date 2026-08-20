import AppKit
import Combine
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class StatusItemController: NSObject {
    private let model: PetViewModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    init(model: PetViewModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: 44)
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
        button.wantsLayer = true
        button.layer?.masksToBounds = false
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 310, height: 220)
        popover.contentViewController = NSHostingController(rootView: PopoverView(
            model: model,
            onChooseImage: { [weak self] in self?.chooseImage() },
            onVisualSettingsChanged: { [weak self] in self?.refreshStatusItem() },
            onQuit: { NSApplication.shared.terminate(nil) }
        ))
    }

    private func observeModel() {
        model.$state
            .combineLatest(model.$petImage, model.$isPaused)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.refreshStatusItem() }
            .store(in: &cancellables)
        model.$cpuUsage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.statusItem.button?.setAccessibilityLabel(self.model.accessibilitySummary)
            }
            .store(in: &cancellables)
    }

    func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || model.isPaused
        button.image = PetRenderer.render(
            source: model.petImage,
            state: model.state,
            phase: 0,
            reduceMotion: true
        )
        button.setAccessibilityLabel(model.accessibilitySummary)
        button.layer?.removeAllAnimations()
        guard !reduceMotion else { return }

        let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bounce.values = [0, amplitude(for: model.state), 0]
        bounce.keyTimes = [0, 0.5, 1]

        let tilt = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        let radians = tiltRadians(for: model.state)
        tilt.values = [0, radians, 0]
        tilt.keyTimes = [0, 0.5, 1]

        let group = CAAnimationGroup()
        group.animations = [bounce, tilt]
        group.duration = duration(for: model.state)
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        group.isRemovedOnCompletion = false
        button.layer?.add(group, forKey: "pet-motion")
    }

    private func duration(for state: PetState) -> CFTimeInterval {
        switch state {
        case .resting: 1.4
        case .normal: 0.8
        case .running: 0.52
        case .sweating: 0.4
        case .onFire: 0.3
        }
    }

    private func amplitude(for state: PetState) -> CGFloat {
        switch state {
        case .resting: 0.5
        case .normal: 1
        case .running: 1.5
        case .sweating, .onFire: 2
        }
    }

    private func tiltRadians(for state: PetState) -> CGFloat {
        switch state {
        case .resting, .normal: 0
        case .running: -0.04
        case .sweating: -0.07
        case .onFire: -0.1
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func chooseImage() {
        popover.performClose(nil)
        let panel = NSOpenPanel()
        panel.title = "ペットにする画像を選ぶ"
        panel.message = "権利を持つ画像を選んでください。画像はこのMac内だけで処理します。"
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importPetImage(from: url)
        refreshStatusItem()
    }
}
