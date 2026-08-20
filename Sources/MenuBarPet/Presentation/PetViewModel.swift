import AppKit
import Combine
import Foundation

@MainActor
final class PetViewModel: ObservableObject {
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var state: PetState = .normal
    @Published private(set) var petImage: NSImage?
    @Published private(set) var statusMessage = "Macの状態を確認中…"
    @Published var isPaused: Bool
    @Published var sensitivity: Sensitivity

    private let cpuSampler: CPUSampling
    private let settingsStore: SettingsStoring
    private let imageStore: PetImageStoring
    private var machine = PetStateMachine()
    private var sampleTimer: Timer?

    init(cpuSampler: CPUSampling, settingsStore: SettingsStoring, imageStore: PetImageStoring) {
        self.cpuSampler = cpuSampler
        self.settingsStore = settingsStore
        self.imageStore = imageStore
        let settings = settingsStore.load()
        isPaused = settings.isPaused
        sensitivity = settings.sensitivity
        if let data = imageStore.loadProcessedImage() {
            petImage = NSImage(data: data)
        }
    }

    var accessibilitySummary: String {
        isPaused ? "メニューバーペット、一時停止中" : "メニューバーペット、\(state.displayName)、CPU \(Int(cpuUsage.rounded()))パーセント"
    }

    func start() {
        guard !isPaused else {
            statusMessage = "一時停止中"
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
            statusMessage = "一時停止中"
        } else {
            start()
        }
    }

    func setSensitivity(_ newValue: Sensitivity) {
        sensitivity = newValue
        machine.reset()
        state = .normal
        saveSettings()
    }

    func importPetImage(from url: URL) {
        do {
            let data = try imageStore.importImage(from: url)
            guard let image = NSImage(data: data) else { throw PetImageStoreError.unreadableImage }
            petImage = image
            statusMessage = "画像をこのMac内に保存しました"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func useStandardPet() {
        do {
            try imageStore.deleteImage()
            petImage = nil
            statusMessage = "標準ペットに戻しました"
        } catch {
            statusMessage = "画像を削除できませんでした"
        }
    }

    func handleWake() {
        machine.reset()
        state = .normal
        if !isPaused { start() }
    }

    @objc private func sampleCPU() {
        guard let usage = cpuSampler.readUsage() else { return }
        let snapshot = machine.ingest(usage, sensitivity: sensitivity)
        cpuUsage = snapshot.smoothedUsage
        state = snapshot.state
        statusMessage = "CPU \(Int(snapshot.smoothedUsage.rounded()))%・\(state.displayName)"
    }

    private func saveSettings() {
        settingsStore.save(AppSettings(isPaused: isPaused, sensitivity: sensitivity))
    }
}
