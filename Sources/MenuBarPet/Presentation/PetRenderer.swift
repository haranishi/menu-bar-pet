import AppKit
import MenuBarPetCore

@MainActor
enum PetRenderer {
    static let pointSize = NSSize(width: 42, height: 22)

    // Retain only the current character/state/appearance, with 96 poses per layer.
    private struct CacheContext: Equatable {
        let character: PetCharacter
        let state: PetState
        let dark: Bool
        let reduced: Bool
        let customIDs: [ObjectIdentifier]
    }
    private static var cacheContext: CacheContext?
    private static var bodyFrames: [Int: NSImage] = [:]
    private static var wheelFrames: [Int: NSImage] = [:]
    static var cachedFrameCount: Int { bodyFrames.count + wheelFrames.count }

    static func render(
        character: PetCharacter, state: PetState, phase: Double,
        wheelPhase: Double? = nil, isDarkAppearance: Bool, reduceMotion: Bool,
        customFrames: [NSImage] = []
    ) -> NSImage {
        let context = CacheContext(
            character: character, state: state, dark: isDarkAppearance, reduced: reduceMotion,
            customIDs: character == .custom ? customFrames.map(ObjectIdentifier.init) : []
        )
        if cacheContext != context {
            bodyFrames.removeAll(keepingCapacity: true)
            wheelFrames.removeAll(keepingCapacity: true)
            cacheContext = context
        }
        let index = reduceMotion ? 0 : PetMotion.frameIndex(phase: phase, frameCount: 96)
        let sampledPhase = Double(index) / 96
        if character == .hamsterWheel {
            // Five identical spokes: cache one spoke interval independently of the gait.
            let wheelIndex = state == .resting || reduceMotion ? 0
                : PetMotion.frameIndex(phase: (wheelPhase ?? phase) * 5, frameCount: 24)
            if wheelFrames[wheelIndex] == nil {
                let frame = HamsterMotion.frame(state: state, phase: 0,
                    wheelPhase: Double(wheelIndex) / 120, reduceMotion: reduceMotion)
                wheelFrames[wheelIndex] = image {
                    drawWheelHardware(frame: frame, isDarkAppearance: isDarkAppearance)
                }
            }
            if bodyFrames[index] == nil {
                let frame = HamsterMotion.frame(state: state, phase: sampledPhase, reduceMotion: reduceMotion)
                bodyFrames[index] = image {
                    if state == .resting {
                        drawSleepingHamster(frame: frame, isDarkAppearance: isDarkAppearance)
                    } else { drawRunningHamster(frame: frame) }
                    drawHamsterOverlay(state: state, pulse: frame.overlayPulse)
                }
            }
            return image {
                wheelFrames[wheelIndex]?.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
                bodyFrames[index]?.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            }
        }
        let bodyIndex = character == .custom
            ? (state == .resting || reduceMotion ? 0 : PetMotion.frameIndex(phase: phase, frameCount: customFrames.count))
            : index
        if let cached = bodyFrames[bodyIndex] { return cached }
        let output = renderUncached(character: character, state: state,
            phase: character == .custom ? phase : sampledPhase, wheelPhase: wheelPhase,
            isDarkAppearance: isDarkAppearance, reduceMotion: reduceMotion, customFrames: customFrames)
        bodyFrames[bodyIndex] = output
        return output
    }

    static func preview(character: PetCharacter, state: PetState, isDarkAppearance: Bool,
        customFrames: [NSImage] = []) -> NSImage {
        renderUncached(character: character, state: state, phase: 0.18,
            isDarkAppearance: isDarkAppearance, reduceMotion: true, customFrames: customFrames)
    }

    private static func image(_ draw: () -> Void) -> NSImage {
        guard let bitmap = makeBitmap(pointSize: pointSize) else { return NSImage(size: pointSize) }
        withContext(bitmap, draw: draw)
        let image = NSImage(size: pointSize)
        image.addRepresentation(bitmap)
        return image
    }

    private static func renderUncached(
        character: PetCharacter,
        state: PetState,
        phase: Double,
        wheelPhase: Double? = nil,
        isDarkAppearance: Bool,
        reduceMotion: Bool,
        customFrames: [NSImage] = []
    ) -> NSImage {
        guard let bitmap = makeBitmap(pointSize: pointSize) else { return NSImage(size: pointSize) }

        withContext(bitmap) {
            NSColor.clear.setFill()
            NSRect(origin: .zero, size: pointSize).fill()
            switch character {
            case .shibaInu:
                drawShiba(
                    state: state,
                    frame: ShibaMotion.frame(
                        state: state,
                        phase: phase,
                        reduceMotion: reduceMotion
                    ),
                    isDarkAppearance: isDarkAppearance
                )
            case .hamsterWheel:
                let frame = HamsterMotion.frame(
                    state: state,
                    phase: phase,
                    wheelPhase: wheelPhase,
                    reduceMotion: reduceMotion
                )
                drawHamsterWheel(
                    state: state,
                    frame: frame,
                    isDarkAppearance: isDarkAppearance
                )
            case .custom:
                guard !customFrames.isEmpty else { return }
                let index = state == .resting || reduceMotion
                    ? 0
                    : PetMotion.frameIndex(phase: phase, frameCount: customFrames.count)
                drawCustomFrame(customFrames[index])
            }
        }

        let output = NSImage(size: pointSize)
        output.addRepresentation(bitmap)
        output.isTemplate = false
        return output
    }

    private static func drawShiba(
        state: PetState,
        frame: ShibaMotionFrame,
        isDarkAppearance: Bool
    ) {
        let outline = isDarkAppearance
            ? NSColor(calibratedWhite: 0.90, alpha: 0.95)
            : NSColor(calibratedRed: 0.24, green: 0.13, blue: 0.08, alpha: 0.96)

        NSColor.black.withAlphaComponent(frame.shadowOpacity).setFill()
        let shadowWidth = CGFloat(27 * frame.shadowScale)
        NSBezierPath(ovalIn: NSRect(
            x: 22.5 - shadowWidth / 2,
            y: 0.55,
            width: shadowWidth,
            height: 1.35
        )).fill()

        if state == .resting {
            drawSleepingShiba(frame: frame, outline: outline, isDarkAppearance: isDarkAppearance)
        } else {
            drawRunningShiba(
                frame: frame,
                outline: outline,
                isDarkAppearance: isDarkAppearance
            )
        }
        drawShibaOverlay(state: state, pulse: frame.overlayPulse)
    }

    private static func drawRunningShiba(
        frame: ShibaMotionFrame,
        outline: NSColor,
        isDarkAppearance: Bool
    ) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let bounce = CGFloat(frame.bounceHeight)
        let lean = CGFloat(frame.forwardLean)
        let pose = NSAffineTransform()
        pose.translateX(by: 23, yBy: 8)
        pose.rotate(byDegrees: -lean * 1.8)
        pose.scaleX(by: CGFloat(frame.bodyScaleX), yBy: CGFloat(frame.bodyScaleY))
        pose.translateX(by: -23, yBy: -8)
        pose.translateX(by: 0, yBy: bounce)
        pose.concat()

        let fur = NSColor(calibratedRed: 0.82, green: 0.39, blue: 0.12, alpha: 1)
        let cream = NSColor(calibratedRed: 1.00, green: 0.91, blue: 0.75, alpha: 1)
        let darkFur = NSColor(calibratedRed: 0.47, green: 0.20, blue: 0.07, alpha: 1)
        let facial = NSColor(calibratedRed: 0.20, green: 0.10, blue: 0.06, alpha: 1)
        let strideAmount = 2.8 * CGFloat(frame.forwardLean / 0.8)
        let headX = lean - 1.6

        // Far / near legs are staggered. Contact feet stay on the floor while the body rises.
        for (x, phase, alpha) in [
            (13.0, frame.rearLegPhase + 0.08, 0.62), (29.0, frame.frontLegPhase + 0.08, 0.62),
            (17.0, frame.rearLegPhase, 1.0), (33.0, frame.frontLegPhase, 1.0),
        ] {
            let step = RunnerGait.step(phase: phase, stride: Double(strideAmount))
            let foot = NSPoint(x: x + step.x, y: 1.8 - bounce + step.lift)
            let knee = NSPoint(x: x + step.x * 0.45 - step.lift * 0.25, y: 4.2 + step.lift * 0.4)
            darkFur.withAlphaComponent(alpha).setStroke()
            let leg = NSBezierPath()
            leg.lineWidth = CGFloat(ShibaMotion.limbStrokeWidth)
            leg.lineCapStyle = .round
            leg.move(to: NSPoint(x: x, y: 7.2))
            leg.curve(to: foot, controlPoint1: knee,
                controlPoint2: NSPoint(x: foot.x - 0.4, y: foot.y + 1.1))
            leg.stroke()
            cream.withAlphaComponent(alpha).setStroke()
            let sock = NSBezierPath()
            sock.lineWidth = 1.15
            sock.lineCapStyle = .round
            sock.move(to: NSPoint(x: foot.x - 0.25, y: foot.y + 0.65))
            sock.line(to: foot)
            sock.stroke()
        }

        // 輪郭→柴色→白い尾先の順で太い巻き尾を作る。
        let tail = NSBezierPath()
        tail.lineCapStyle = .round
        tail.move(to: NSPoint(x: 11.0, y: 11.0))
        tail.curve(
            to: NSPoint(x: 5.0, y: 17.0 + CGFloat(frame.tailSwing)),
            controlPoint1: NSPoint(x: 7.4, y: 11.0),
            controlPoint2: NSPoint(x: 4.2, y: 13.2)
        )
        tail.curve(
            to: NSPoint(x: 9.7, y: 15.4),
            controlPoint1: NSPoint(x: 6.0, y: 20.0),
            controlPoint2: NSPoint(x: 10.7, y: 19.0)
        )
        outline.setStroke()
        tail.lineWidth = CGFloat(ShibaMotion.tailStrokeWidth + 1.0)
        tail.stroke()
        fur.setStroke()
        tail.lineWidth = CGFloat(ShibaMotion.tailStrokeWidth)
        tail.stroke()
        let tailTipCream = isDarkAppearance
            ? NSColor(calibratedRed: 1.00, green: 0.95, blue: 0.86, alpha: 1)
            : cream
        tailTipCream.setStroke()
        let tailTip = NSBezierPath()
        tailTip.lineCapStyle = .round
        tailTip.lineWidth = 1.75
        tailTip.move(to: NSPoint(x: 5.05, y: 16.95 + CGFloat(frame.tailSwing)))
        tailTip.curve(
            to: NSPoint(x: 7.1, y: 17.85),
            controlPoint1: NSPoint(x: 5.5, y: 17.9),
            controlPoint2: NSPoint(x: 6.3, y: 18.1)
        )
        tailTip.stroke()

        let body = NSBezierPath(ovalIn: NSRect(x: 9.8, y: 6.0, width: 24.5, height: 9.7))
        fur.setFill()
        body.fill()
        outline.setStroke()
        body.lineWidth = CGFloat(ShibaMotion.primaryStrokeWidth)
        body.stroke()

        let head = NSBezierPath(ovalIn: NSRect(x: 29.1 + headX, y: 8.0, width: 10.0, height: 9.8))
        fur.setFill()
        head.fill()
        outline.setStroke()
        head.lineWidth = CGFloat(ShibaMotion.primaryStrokeWidth)
        head.stroke()

        for points in [
            [NSPoint(x: 30.2 + headX, y: 15.0), NSPoint(x: 31.7 + headX, y: 18.5), NSPoint(x: 34.0 + headX, y: 16.2)],
            [NSPoint(x: 34.3 + headX, y: 16.1), NSPoint(x: 36.7 + headX, y: 18.3), NSPoint(x: 37.5 + headX, y: 14.9)],
        ] {
            let ear = NSBezierPath()
            ear.move(to: points[0])
            ear.line(to: points[1])
            ear.line(to: points[2])
            ear.close()
            fur.setFill()
            ear.fill()
            outline.setStroke()
            ear.lineWidth = CGFloat(ShibaMotion.primaryStrokeWidth)
            ear.lineJoinStyle = .round
            ear.stroke()
        }

        cream.setFill()
        NSBezierPath(ovalIn: NSRect(x: 19.2, y: 6.2, width: 12.4, height: 6.1)).fill()
        NSBezierPath(ovalIn: NSRect(x: 34.0 + headX, y: 9.0, width: 6.0, height: 5.1)).fill()

        facial.setFill()
        NSBezierPath(ovalIn: NSRect(x: 34.5 + headX, y: 12.9, width: 1.25, height: 1.25)).fill()
        NSBezierPath(ovalIn: NSRect(x: 38.7 + headX, y: 10.8, width: 1.45, height: 1.25)).fill()
    }

    private static func drawSleepingShiba(
        frame: ShibaMotionFrame,
        outline: NSColor,
        isDarkAppearance: Bool
    ) {
        let fur = NSColor(calibratedRed: 0.82, green: 0.39, blue: 0.12, alpha: 1)
        let cream = NSColor(calibratedRed: 1.00, green: 0.91, blue: 0.75, alpha: 1)
        let facial = NSColor(calibratedRed: 0.20, green: 0.10, blue: 0.06, alpha: 1)
        let breathing = CGFloat(frame.breathingOffset)

        outline.setStroke()
        let curledTail = NSBezierPath()
        curledTail.lineWidth = CGFloat(ShibaMotion.tailStrokeWidth + 0.9)
        curledTail.lineCapStyle = .round
        curledTail.move(to: NSPoint(x: 11.0, y: 7.0))
        curledTail.curve(
            to: NSPoint(x: 7.0, y: 12.8),
            controlPoint1: NSPoint(x: 5.2, y: 7.1),
            controlPoint2: NSPoint(x: 5.5, y: 12.6)
        )
        curledTail.curve(
            to: NSPoint(x: 11.5, y: 12.0),
            controlPoint1: NSPoint(x: 8.5, y: 15.2),
            controlPoint2: NSPoint(x: 12.8, y: 14.3)
        )
        curledTail.stroke()
        fur.setStroke()
        curledTail.lineWidth = CGFloat(ShibaMotion.tailStrokeWidth)
        curledTail.stroke()

        let body = NSBezierPath(ovalIn: NSRect(
            x: 8.3 - breathing / 2,
            y: 3.0 - breathing / 2,
            width: 25.8 + breathing,
            height: 12.6 + breathing
        ))
        fur.setFill()
        body.fill()
        outline.setStroke()
        body.lineWidth = CGFloat(ShibaMotion.primaryStrokeWidth)
        body.stroke()

        // 伏せた頭でも三角耳と白マズルを残し、犬種の判別点を保つ。
        let head = NSBezierPath(ovalIn: NSRect(x: 27.5, y: 3.0, width: 9.5, height: 9.0))
        fur.setFill()
        head.fill()
        outline.setStroke()
        head.lineWidth = CGFloat(ShibaMotion.primaryStrokeWidth)
        head.stroke()
        for points in [
            [NSPoint(x: 28.1, y: 10.1), NSPoint(x: 29.7, y: 15.9), NSPoint(x: 32.0, y: 10.9)],
            [NSPoint(x: 32.0, y: 10.7), NSPoint(x: 34.7, y: 15.0), NSPoint(x: 35.4, y: 9.4)],
        ] {
            let ear = NSBezierPath()
            ear.move(to: points[0])
            ear.line(to: points[1])
            ear.line(to: points[2])
            ear.close()
            fur.setFill()
            ear.fill()
            outline.setStroke()
            ear.lineWidth = CGFloat(ShibaMotion.primaryStrokeWidth)
            ear.lineJoinStyle = .round
            ear.stroke()
        }
        cream.setFill()
        NSBezierPath(ovalIn: NSRect(x: 17.0, y: 3.2, width: 12.8, height: 6.0)).fill()
        NSBezierPath(ovalIn: NSRect(x: 31.4, y: 3.3, width: 5.9, height: 4.8)).fill()

        facial.setStroke()
        let eye = NSBezierPath()
        eye.lineWidth = 1.0
        eye.lineCapStyle = .round
        eye.move(to: NSPoint(x: 31.1, y: 8.1))
        eye.curve(
            to: NSPoint(x: 33.0, y: 8.0),
            controlPoint1: NSPoint(x: 31.7, y: 7.6),
            controlPoint2: NSPoint(x: 32.4, y: 7.6)
        )
        eye.stroke()
        facial.setFill()
        NSBezierPath(ovalIn: NSRect(x: 35.8, y: 5.1, width: 1.4, height: 1.2)).fill()

        let markColor = isDarkAppearance
            ? NSColor(calibratedWhite: 0.84, alpha: 0.95)
            : NSColor(calibratedWhite: 0.28, alpha: 0.92)
        markColor.setStroke()
        let marks = NSBezierPath()
        marks.lineWidth = 0.8
        marks.lineCapStyle = .round
        marks.move(to: NSPoint(x: 34.1, y: 17.0))
        marks.line(to: NSPoint(x: 36.2, y: 17.0))
        marks.line(to: NSPoint(x: 34.1, y: 15.2))
        marks.line(to: NSPoint(x: 36.2, y: 15.2))
        marks.move(to: NSPoint(x: 36.9, y: 20.4))
        marks.line(to: NSPoint(x: 38.0, y: 19.6))
        marks.line(to: NSPoint(x: 36.1, y: 17.9))
        marks.line(to: NSPoint(x: 38.0, y: 17.9))
        marks.stroke()
    }

    private static func drawShibaOverlay(state: PetState, pulse: Double) {
        let center: NSPoint = switch state {
        case .sweating: NSPoint(x: 39.75, y: 19.3)
        case .onFire: NSPoint(x: 3.1, y: 9.4)
        default: .zero
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.scale(by: pulse)
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.concat()

        switch state {
        case .sweating:
            NSColor.systemBlue.setFill()
            let drop = NSBezierPath()
            drop.move(to: NSPoint(x: 39.8, y: 21.2))
            drop.curve(
                to: NSPoint(x: 38.4, y: 18.0),
                controlPoint1: NSPoint(x: 38.5, y: 19.8),
                controlPoint2: NSPoint(x: 38.0, y: 18.7)
            )
            drop.curve(
                to: NSPoint(x: 39.8, y: 21.2),
                controlPoint1: NSPoint(x: 40.8, y: 18.0),
                controlPoint2: NSPoint(x: 41.0, y: 19.8)
            )
            drop.fill()
        case .onFire:
            let flame = NSBezierPath()
            flame.move(to: NSPoint(x: 4.8, y: 3.7))
            flame.curve(
                to: NSPoint(x: 1.0, y: 8.4),
                controlPoint1: NSPoint(x: 2.2, y: 3.5),
                controlPoint2: NSPoint(x: 0.7, y: 5.7)
            )
            flame.curve(
                to: NSPoint(x: 3.0, y: 15.0),
                controlPoint1: NSPoint(x: 1.1, y: 11.2),
                controlPoint2: NSPoint(x: 3.3, y: 12.4)
            )
            flame.curve(
                to: NSPoint(x: 5.2, y: 4.0),
                controlPoint1: NSPoint(x: 6.2, y: 11.2),
                controlPoint2: NSPoint(x: 6.0, y: 6.1)
            )
            flame.close()
            NSColor.systemRed.setFill()
            flame.fill()
            NSColor.systemYellow.setFill()
            NSBezierPath(ovalIn: NSRect(x: 2.4, y: 5.0, width: 2.0, height: 6.4)).fill()
        default:
            break
        }
    }

    private static func drawCustomFrame(_ image: NSImage) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let height: CGFloat = 18
        let width = min(pointSize.width, height * image.size.width / image.size.height)
        let fittedHeight = width * image.size.height / image.size.width
        let destination = NSRect(
            x: (pointSize.width - width) / 2,
            y: (pointSize.height - fittedHeight) / 2,
            width: width,
            height: fittedHeight
        )
        image.draw(
            in: destination,
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    static func pngData(images: [NSImage], backgroundColor: NSColor, pointSize: NSSize) -> Data? {
        guard let bitmap = makeBitmap(pointSize: pointSize) else { return nil }
        withContext(bitmap) {
            backgroundColor.setFill()
            NSRect(origin: .zero, size: pointSize).fill()
            for (index, image) in images.enumerated() {
                image.draw(
                    in: NSRect(
                        x: CGFloat(index) * Self.pointSize.width,
                        y: 0,
                        width: Self.pointSize.width,
                        height: Self.pointSize.height
                    ),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            }
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func makeBitmap(pointSize: NSSize) -> NSBitmapImageRep? {
        let scale = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(pointSize.width * CGFloat(scale))),
            pixelsHigh: Int(ceil(pointSize.height * CGFloat(scale))),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = pointSize
        return bitmap
    }

    private static func withContext(_ bitmap: NSBitmapImageRep, draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        draw()
        context.flushGraphics()
    }

    private static func drawHamsterWheel(
        state: PetState,
        frame: HamsterMotionFrame,
        isDarkAppearance: Bool
    ) {
        drawWheelHardware(frame: frame, isDarkAppearance: isDarkAppearance)

        if state == .resting {
            drawSleepingHamster(frame: frame, isDarkAppearance: isDarkAppearance)
        } else {
            drawRunningHamster(frame: frame)
        }

        drawHamsterOverlay(state: state, pulse: frame.overlayPulse)
    }

    private static func drawWheelHardware(frame: HamsterMotionFrame, isDarkAppearance: Bool) {
        let center = NSPoint(x: HamsterMotion.wheelCenter.x, y: HamsterMotion.wheelCenter.y)
        NSColor.black.withAlphaComponent(0.14).setFill()
        NSBezierPath(ovalIn: NSRect(x: 14.2, y: 0.1, width: 13.6, height: 1)).fill()

        let hardware = isDarkAppearance
            ? NSColor(calibratedWhite: 0.55, alpha: 0.75)
            : NSColor(calibratedWhite: 0.42, alpha: 0.85)

        hardware.withAlphaComponent(0.65).setStroke()
        let radius = CGFloat(HamsterMotion.wheelRadius)
        let outerRect = NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let innerRect = outerRect.insetBy(dx: 1.15, dy: 1.15)
        let outer = NSBezierPath(ovalIn: outerRect)
        outer.lineWidth = 1.2
        outer.stroke()
        let inner = NSBezierPath(ovalIn: innerRect)
        inner.lineWidth = 0.7
        inner.stroke()

        NSGraphicsContext.saveGraphicsState()
        let spokeTransform = NSAffineTransform()
        spokeTransform.translateX(by: center.x, yBy: center.y)
        spokeTransform.rotate(byRadians: frame.wheelAngle)
        spokeTransform.translateX(by: -center.x, yBy: -center.y)
        spokeTransform.concat()
        hardware.withAlphaComponent(0.55).setStroke()
        let spokes = NSBezierPath()
        spokes.lineWidth = 0.75
        for index in 0..<HamsterMotion.spokeCount {
            let angle = Double(index) * 2 * .pi / Double(HamsterMotion.spokeCount)
            spokes.move(to: center)
            spokes.line(to: NSPoint(
                x: center.x + 8.6 * cos(angle),
                y: center.y + 8.6 * sin(angle)
            ))
        }
        spokes.stroke()
        NSGraphicsContext.restoreGraphicsState()

        hardware.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: center.x - 0.95,
            y: center.y - 0.95,
            width: 1.9,
            height: 1.9
        )).fill()

    }

    private static func applyBodyScale(pivot: MotionPoint) {
        let transform = NSAffineTransform()
        transform.translateX(by: CGFloat(pivot.x), yBy: CGFloat(pivot.y))
        transform.scale(by: CGFloat(HamsterMotion.bodyScale))
        transform.translateX(by: CGFloat(-pivot.x), yBy: CGFloat(-pivot.y))
        transform.concat()
    }

    private static func drawRunningHamster(frame: HamsterMotionFrame) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        applyBodyScale(pivot: HamsterMotion.runningBodyPivot)
        let offset = CGFloat(frame.bodyOffsetY)
        let fur = NSColor(calibratedRed: 0.72, green: 0.42, blue: 0.16, alpha: 1)
        let belly = NSColor(calibratedRed: 0.96, green: 0.87, blue: 0.72, alpha: 1)
        let limb = NSColor(calibratedRed: 0.55, green: 0.27, blue: 0.10, alpha: 1)

        limb.setStroke()
        // 拡大した体でも内輪に収まるよう、尻尾は真横ではなく体沿いに跳ね上げる
        let tail = NSBezierPath()
        tail.lineWidth = 1.35
        tail.lineCapStyle = .round
        tail.move(to: NSPoint(x: 17.2, y: 7.0 + offset))
        tail.curve(
            to: NSPoint(x: 15.9, y: 8.6 + offset),
            controlPoint1: NSPoint(x: 16.5, y: 7.2 + offset),
            controlPoint2: NSPoint(x: 16.0, y: 8.0 + offset)
        )
        tail.stroke()

        let frontStride = CGFloat(sin(frame.frontLegPhase * 2 * .pi))
        let rearStride = CGFloat(sin(frame.rearLegPhase * 2 * .pi))
        for (x, stride) in [(19.0, rearStride), (20.5, rearStride), (24.2, frontStride), (25.6, frontStride)] {
            let leg = NSBezierPath()
            leg.lineWidth = 1.2
            leg.lineCapStyle = .round
            leg.move(to: NSPoint(x: x, y: 5.8 + offset))
            leg.line(to: NSPoint(
                x: x - stride * 1.25 * CGFloat(frame.movementIntensity),
                y: 3.3 + abs(stride) * 0.45
            ))
            leg.stroke()
        }

        fur.setFill()
        NSBezierPath(ovalIn: NSRect(x: 16.8, y: 5.1 + offset, width: 9.7, height: 7.1)).fill()
        NSBezierPath(ovalIn: NSRect(x: 23.5, y: 6.1 + offset, width: 5.0, height: 5.3)).fill()
        limb.setFill()
        NSBezierPath(ovalIn: NSRect(x: 24.0, y: 11.3 + offset, width: 2.2, height: 2.2)).fill()

        belly.setFill()
        NSBezierPath(ovalIn: NSRect(x: 20.0, y: 5.35 + offset, width: 5.4, height: 4.8)).fill()

        NSColor.labelColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 26.4, y: 8.7 + offset, width: 0.85, height: 0.85)).fill()
        NSColor.systemPink.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: 28.0, y: 7.65 + offset, width: 0.65, height: 0.55)).fill()
    }

    private static func drawSleepingHamster(
        frame: HamsterMotionFrame,
        isDarkAppearance: Bool
    ) {
        NSGraphicsContext.saveGraphicsState()
        applyBodyScale(pivot: HamsterMotion.sleepingBodyPivot)
        let breathing = CGFloat(frame.breathingOffset)
        let fur = NSColor(calibratedRed: 0.72, green: 0.42, blue: 0.16, alpha: 1)
        let bodyRect = NSRect(
            x: 16.4 - breathing / 2,
            y: 4.3 - breathing / 2,
            width: 10.6 + breathing,
            height: 8.5 + breathing
        )
        fur.setFill()
        NSBezierPath(ovalIn: bodyRect).fill()
        NSBezierPath(ovalIn: NSRect(x: 24.0, y: 4.6, width: 4.2, height: 4.5)).fill()
        NSBezierPath(ovalIn: NSRect(x: 24.0, y: 8.8, width: 1.9, height: 1.9)).fill()

        NSColor(calibratedRed: 0.96, green: 0.87, blue: 0.72, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 20.1, y: 4.7, width: 5.0, height: 4.3)).fill()

        NSColor.labelColor.setStroke()
        let eye = NSBezierPath()
        eye.lineWidth = 0.62
        eye.lineCapStyle = .round
        eye.move(to: NSPoint(x: 25.65, y: 7.05))
        eye.curve(
            to: NSPoint(x: 26.45, y: 7.02),
            controlPoint1: NSPoint(x: 25.9, y: 6.85),
            controlPoint2: NSPoint(x: 26.2, y: 6.85)
        )
        eye.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // 「Z」は本体ではないので拡大しない
        let sleepMarkColor = isDarkAppearance
            ? NSColor(calibratedWhite: 0.78, alpha: 0.9)
            : NSColor(calibratedWhite: 0.25, alpha: 0.9)
        sleepMarkColor.setStroke()
        let sleepMarks = NSBezierPath()
        sleepMarks.lineWidth = 0.55
        sleepMarks.lineCapStyle = .round
        sleepMarks.move(to: NSPoint(x: 28.2, y: 14.6))
        sleepMarks.line(to: NSPoint(x: 29.3, y: 14.6))
        sleepMarks.line(to: NSPoint(x: 28.2, y: 13.5))
        sleepMarks.line(to: NSPoint(x: 29.3, y: 13.5))
        sleepMarks.move(to: NSPoint(x: 29.7, y: 16.3))
        sleepMarks.line(to: NSPoint(x: 30.9, y: 16.3))
        sleepMarks.line(to: NSPoint(x: 29.7, y: 15.1))
        sleepMarks.line(to: NSPoint(x: 30.9, y: 15.1))
        sleepMarks.stroke()
    }

    // 拡大した尻尾が元の炎の位置に届くので、炎だけ左へ寄せて重なりを避ける。
    // 縦は回し車の中心が 0.5pt 下がったぶん、両方のオーバーレイを追随させる。
    private static let flameShiftX: CGFloat = -2.5
    private static let overlayShiftY: CGFloat = -0.5

    private static func drawHamsterOverlay(state: PetState, pulse: Double) {
        let shiftX: CGFloat = state == .onFire ? flameShiftX : 0
        let center: NSPoint = switch state {
        case .sweating: NSPoint(x: 32.6, y: 17.5 + overlayShiftY)
        case .onFire: NSPoint(x: 9.2 + shiftX, y: 9.9 + overlayShiftY)
        default: .zero
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.scale(by: pulse)
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.translateX(by: shiftX, yBy: overlayShiftY)
        transform.concat()

        switch state {
        case .sweating:
            NSColor.systemBlue.setFill()
            let drop = NSBezierPath()
            drop.move(to: NSPoint(x: 33.0, y: 18.9))
            drop.curve(
                to: NSPoint(x: 31.7, y: 16.1),
                controlPoint1: NSPoint(x: 31.8, y: 17.4),
                controlPoint2: NSPoint(x: 31.4, y: 16.6)
            )
            drop.curve(
                to: NSPoint(x: 33.0, y: 18.9),
                controlPoint1: NSPoint(x: 33.7, y: 16.2),
                controlPoint2: NSPoint(x: 33.8, y: 17.7)
            )
            drop.fill()
        case .onFire:
            let flame = NSBezierPath()
            flame.move(to: NSPoint(x: 10.5, y: 4.0))
            flame.curve(
                to: NSPoint(x: 6.0, y: 8.0),
                controlPoint1: NSPoint(x: 7.3, y: 4.0),
                controlPoint2: NSPoint(x: 5.8, y: 5.9)
            )
            flame.curve(
                to: NSPoint(x: 9.4, y: 15.8),
                controlPoint1: NSPoint(x: 6.2, y: 11.6),
                controlPoint2: NSPoint(x: 9.2, y: 12.2)
            )
            flame.curve(
                to: NSPoint(x: 11.0, y: 4.2),
                controlPoint1: NSPoint(x: 13.0, y: 11.2),
                controlPoint2: NSPoint(x: 12.6, y: 6.4)
            )
            flame.close()
            NSColor.systemRed.setFill()
            flame.fill()
            NSColor.systemYellow.setFill()
            NSBezierPath(ovalIn: NSRect(x: 8.1, y: 5.0, width: 2.2, height: 6.0)).fill()
        default:
            break
        }
    }

}
