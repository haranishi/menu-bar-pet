import Foundation

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
protocol PetImageStoring: AnyObject {
    func loadProcessedImage() -> Data?
    func importImage(from sourceURL: URL) throws -> Data
    func deleteImage() throws
}
