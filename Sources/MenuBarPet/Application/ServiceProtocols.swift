import Foundation
import MenuBarPetCore

@MainActor
protocol CPUSampling: AnyObject {
    func readUsage() -> Double?
    func reset()
}

@MainActor
protocol SettingsStoring: AnyObject {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

@MainActor
protocol AIUsageProviding: AnyObject {
    var snapshots: [AIUsageSnapshot] { get }
    func refresh()
    /// 読み取りを回すかどうか。常駐中に無駄なディスクアクセスをしないための入り切り。
    func setActive(_ active: Bool)
}
