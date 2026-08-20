import Foundation

enum PetState: Int, Codable, CaseIterable, Sendable {
    case resting
    case normal
    case running
    case sweating
    case onFire

    var displayName: String {
        switch self {
        case .resting: "休息中"
        case .normal: "通常"
        case .running: "疾走中"
        case .sweating: "汗だく"
        case .onFire: "全力"
        }
    }
}

enum Sensitivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case relaxed
    case standard
    case sensitive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .relaxed: "のんびり"
        case .standard: "標準"
        case .sensitive: "敏感"
        }
    }

    var thresholds: [Double] {
        switch self {
        case .relaxed: [30, 60, 80, 95]
        case .standard: [20, 50, 75, 90]
        case .sensitive: [10, 35, 60, 80]
        }
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var isPaused = false
    var sensitivity = Sensitivity.standard
}
