import Foundation

public enum PetState: Int, Codable, CaseIterable, Sendable {
    case resting
    case normal
    case running
    case sweating
    case onFire

    public var displayName: String {
        switch self {
        case .resting: "休息中"
        case .normal: "通常"
        case .running: "疾走中"
        case .sweating: "汗だく"
        case .onFire: "全力"
        }
    }

    public var fileName: String {
        switch self {
        case .resting: "resting"
        case .normal: "normal"
        case .running: "running"
        case .sweating: "sweating"
        case .onFire: "on-fire"
        }
    }
}

public enum PetCharacter: String, Codable, CaseIterable, Identifiable, Sendable {
    case shibaInu
    case hamsterWheel
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .shibaInu: "柴犬"
        case .hamsterWheel: "ハムスター"
        case .custom: "自作ランナー"
        }
    }
}

public enum Sensitivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case relaxed
    case standard
    case sensitive

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .relaxed: "のんびり"
        case .standard: "標準"
        case .sensitive: "敏感"
        }
    }

    public var thresholds: [Double] {
        switch self {
        case .relaxed: [30, 60, 80, 95]
        case .standard: [20, 50, 75, 90]
        case .sensitive: [10, 35, 60, 80]
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var isPaused: Bool
    public var character: PetCharacter
    public var metricSource: MetricSource
    public var aiUsageProviders: Set<AIUsageProvider>
    public var showsMenuBarReadout: Bool

    public init(
        isPaused: Bool = false,
        character: PetCharacter = .shibaInu,
        metricSource: MetricSource = .cpu,
        aiUsageProviders: Set<AIUsageProvider> = Set(AIUsageProvider.allCases),
        showsMenuBarReadout: Bool = true
    ) {
        self.isPaused = isPaused
        self.character = character
        self.metricSource = metricSource
        self.aiUsageProviders = aiUsageProviders
        self.showsMenuBarReadout = showsMenuBarReadout
    }

    private enum CodingKeys: String, CodingKey {
        case isPaused
        case character
        case metricSource
        case aiUsageProviders
        case showsMenuBarReadout
    }

    // 旧バージョンが書いた JSON には新しいキーが無いので、未知の値も含めて全部既定値に落とす。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        let rawCharacter = try container.decodeIfPresent(String.self, forKey: .character)
        character = rawCharacter.flatMap(PetCharacter.init(rawValue:)) ?? .shibaInu
        let rawMetricSource = try container.decodeIfPresent(String.self, forKey: .metricSource)
        metricSource = rawMetricSource.flatMap(MetricSource.init(rawValue:)) ?? .cpu
        let rawProviders = try container.decodeIfPresent([String].self, forKey: .aiUsageProviders) ?? []
        let providers = Set(rawProviders.compactMap(AIUsageProvider.init(rawValue:)))
        // 全部オフの設定は「動かす指標が無い」状態なので、保存されていても既定に戻す。
        aiUsageProviders = providers.isEmpty ? Set(AIUsageProvider.allCases) : providers
        showsMenuBarReadout = try container
            .decodeIfPresent(Bool.self, forKey: .showsMenuBarReadout) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isPaused, forKey: .isPaused)
        try container.encode(character.rawValue, forKey: .character)
        try container.encode(metricSource.rawValue, forKey: .metricSource)
        try container.encode(aiUsageProviders.map(\.rawValue).sorted(), forKey: .aiUsageProviders)
        try container.encode(showsMenuBarReadout, forKey: .showsMenuBarReadout)
    }
}
