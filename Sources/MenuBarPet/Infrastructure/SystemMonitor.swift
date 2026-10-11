import Combine
import MenuBarPetCore
import Foundation
import IOKit.ps

struct BatterySnapshot: Equatable {
    let percentage: Int
    let isConnectedToPower: Bool
}

struct SystemSnapshot: Equatable {
    var memoryUsagePercentage = 0
    var availableStorageBytes: Int64 = 0
    var battery: BatterySnapshot?
    var downloadBytesPerSecond = 0.0
    var uploadBytesPerSecond = 0.0
}

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()

    private var timer: Timer?
    private var networkSampler = RustNetworkSampler()
    private var nextStorageSample: TimeInterval = 0
    private var nextBatterySample: TimeInterval = 0
    private var cachedStorageBytes: Int64 = 0
    private var cachedBattery: BatterySnapshot?

    func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(sample),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        networkSampler = RustNetworkSampler()
        nextStorageSample = 0
        nextBatterySample = 0
    }

    @objc private func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        let rates = networkSampler.sample(uptime: now)
        if now >= nextStorageSample {
            cachedStorageBytes = availableStorageBytes()
            nextStorageSample = now + 30
        }
        if now >= nextBatterySample {
            cachedBattery = batterySnapshot()
            nextBatterySample = now + 5
        }
        let updated = SystemSnapshot(
            memoryUsagePercentage: RustNetworkSampler.memoryUsagePercentage(),
            availableStorageBytes: cachedStorageBytes, battery: cachedBattery,
            downloadBytesPerSecond: rates.received, uploadBytesPerSecond: rates.sent
        )
        if snapshot != updated { snapshot = updated }
    }

    private func availableStorageBytes() -> Int64 {
        let values = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func batterySnapshot() -> BatterySnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0,
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let state = description[kIOPSPowerSourceStateKey] as? String
            return BatterySnapshot(
                percentage: min(max(Int((Double(current) / Double(maximum) * 100).rounded()), 0), 100),
                isConnectedToPower: state == kIOPSACPowerValue
            )
        }
        return nil
    }

}
