import CMbpCore
import Foundation

public struct MotionPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct MotionRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

public enum PetMotion {
    public static func normalizedPhase(_ phase: Double) -> Double {
        mbp_phase(phase)
    }

    public static func cycleDuration(cpu: Double) -> Double {
        mbp_cycle_duration(cpu)
    }

    public static func framesPerSecond(
        state: PetState,
        cpu: Double,
        frameCount: Int = 12
    ) -> Double {
        mbp_fps(UInt32(state.rawValue), cpu, Int64(frameCount))
    }

    public static func frameIndex(phase: Double, frameCount: Int) -> Int {
        Int(mbp_frame_index(phase, Int64(frameCount)))
    }

    public static func amplitude(for state: PetState) -> Double {
        mbp_amplitude(UInt32(state.rawValue))
    }
}

public struct PetMotionClock: Equatable, Sendable {
    public private(set) var phase: Double

    public init(phase: Double = 0) {
        self.phase = PetMotion.normalizedPhase(phase)
    }

    public mutating func advance(elapsed: Double, cpu: Double) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        phase = PetMotion.normalizedPhase(phase + elapsed / PetMotion.cycleDuration(cpu: cpu))
    }
}

public struct HamsterMotionFrame: Equatable, Sendable {
    public let wheelAngle: Double
    public let frontLegPhase: Double
    public let rearLegPhase: Double
    public let movementIntensity: Double
    public let bodyOffsetY: Double
    public let breathingOffset: Double
    public let overlayPulse: Double
    public let contentBounds: MotionRect
}

public enum HamsterMotion {
    public static let canvas = MotionRect(x: 0, y: 0, width: 42, height: 22)
    // 台座を廃して回し車を接地線へ直置きしたので、中心は canvas の縦中央に降りる。
    // 外径は「線幅を含めて 21.4pt・上下余白 0.3pt」になるよう path 半径 10.1 + 線幅 1.2 で構成する。
    public static let wheelCenter = MotionPoint(x: 21, y: 11)
    public static let wheelRadius = 10.1
    public static let spokeCount = 5
    // ピボットは足の接地点を新しい内輪の底へ落とす高さに置くので、拡大しても足は床に残る。
    // x は本体が内輪からはみ出す量が最小になる位置（走行時 +0.93pt・睡眠時 +0.51pt）。
    public static let bodyScale = 1.45
    public static let runningBodyPivot = MotionPoint(x: 24.2, y: 4.13)
    public static let sleepingBodyPivot = MotionPoint(x: 25.9, y: 4.5)
    public static let minimumWheelCycleDuration = 0.9
    public static let maximumWheelStepTurns = 0.07
    public static let maximumWheelStepRadians = maximumWheelStepTurns * 2 * Double.pi

    // 拡大前の本体の外接矩形（PetRendererの描画に対応。脚・尻尾・線幅を含み、寝顔の「Z」は含まない）
    public static let runningBodyExtent = MotionRect(x: 15.22, y: 2.7, width: 13.42, height: 11.3)
    public static let sleepingBodyExtent = MotionRect(x: 16.25, y: 4.15, width: 11.95, height: 8.8)

    public static func scaledBodyExtent(state: PetState) -> MotionRect {
        MotionRect(mbp_scaled_body_extent(UInt32(state.rawValue)))
    }

    public static func wheelCycleDuration(cpu: Double) -> Double {
        mbp_wheel_cycle(cpu)
    }

    public static func wheelPhaseIncrement(elapsed: Double, cpu: Double) -> Double {
        mbp_wheel_increment(elapsed, cpu)
    }

    public static func wheelAngle(state: PetState, phase: Double) -> Double {
        mbp_wheel_angle(UInt32(state.rawValue), phase)
    }

    public static func legPhases(phase: Double) -> (front: Double, rear: Double) {
        let front = PetMotion.normalizedPhase(phase * 2)
        return (front, PetMotion.normalizedPhase(front + 0.5))
    }

    public static func frame(
        state: PetState,
        phase: Double,
        wheelPhase: Double? = nil,
        reduceMotion: Bool
    ) -> HamsterMotionFrame {
        let f = mbp_hamster_frame(UInt32(state.rawValue), phase, wheelPhase ?? phase, reduceMotion ? 1 : 0)
        return HamsterMotionFrame(
            wheelAngle: f.wheel_angle, frontLegPhase: f.front, rearLegPhase: f.rear,
            movementIntensity: f.intensity, bodyOffsetY: f.body_offset,
            breathingOffset: f.breathing, overlayPulse: f.overlay_pulse,
            contentBounds: MotionRect(f.bounds)
        )
    }
}

public struct HamsterWheelClock: Equatable, Sendable {
    public private(set) var phase: Double

    public init(phase: Double = 0) {
        self.phase = PetMotion.normalizedPhase(phase)
    }

    public mutating func advance(elapsed: Double, cpu: Double) {
        phase = PetMotion.normalizedPhase(
            phase + HamsterMotion.wheelPhaseIncrement(elapsed: elapsed, cpu: cpu)
        )
    }
}

public struct ShibaMotionFrame: Equatable, Sendable {
    public let frontLegPhase: Double
    public let rearLegPhase: Double
    public let bounceHeight: Double
    public let breathingOffset: Double
    public let bodyScaleX: Double
    public let bodyScaleY: Double
    public let forwardLean: Double
    public let tailSwing: Double
    public let shadowScale: Double
    public let shadowOpacity: Double
    public let overlayPulse: Double
    public let overlayBounds: MotionRect?
    public let contentBounds: MotionRect
}

public enum ShibaMotion {
    public static let canvas = MotionRect(x: 0, y: 0, width: 42, height: 22)
    public static let runningBodyExtent = MotionRect(x: 3.8, y: 1.2, width: 36.4, height: 19.6)
    public static let sleepingBodyExtent = MotionRect(x: 5.2, y: 2.0, width: 32.2, height: 17.8)
    public static let bodyFillExtent = MotionRect(x: 9.6, y: 5.7, width: 29.8, height: 15.1)
    public static let primaryStrokeWidth = 1.4
    public static let limbStrokeWidth = 1.8
    public static let tailStrokeWidth = 2.4
    public static let ascentFraction = 0.35
    public static let sweatBounds = MotionRect(x: 37.7, y: 16.7, width: 4.3, height: 5.3)
    public static let flameBounds = MotionRect(x: 0.3, y: 2.8, width: 5.7, height: 13.1)

    public static func legPhases(state: PetState, phase: Double) -> (front: Double, rear: Double) {
        guard state != .resting else { return (0, 0) }
        let front = PetMotion.normalizedPhase(phase + 0.1)
        return (front, PetMotion.normalizedPhase(front + 0.5))
    }

    // 35%で頂点へ ease-out、残り65%で接地へ ease-in。正弦波にはしない。
    public static func asymmetricBounce(phase: Double) -> Double {
        mbp_bounce(phase)
    }

    public static func overlayBounds(for state: PetState) -> MotionRect? {
        switch state {
        case .sweating: sweatBounds
        case .onFire: flameBounds
        default: nil
        }
    }

    public static func frame(
        state: PetState,
        phase: Double,
        reduceMotion: Bool
    ) -> ShibaMotionFrame {
        let f = mbp_shiba_frame(UInt32(state.rawValue), phase, reduceMotion ? 1 : 0)
        return ShibaMotionFrame(
            frontLegPhase: f.front, rearLegPhase: f.rear, bounceHeight: f.bounce,
            breathingOffset: f.breathing, bodyScaleX: f.scale_x, bodyScaleY: f.scale_y,
            forwardLean: f.lean, tailSwing: f.tail, shadowScale: f.shadow_scale,
            shadowOpacity: f.shadow_opacity, overlayPulse: f.overlay_pulse,
            overlayBounds: f.has_overlay != 0 ? MotionRect(f.overlay) : nil,
            contentBounds: MotionRect(f.bounds)
        )
    }
}

private extension MotionRect {
    init(_ rect: MbpRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
