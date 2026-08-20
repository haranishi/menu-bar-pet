import AppKit

@MainActor
enum PetRenderer {
    static func render(source: NSImage?, state: PetState, phase: Double, reduceMotion: Bool) -> NSImage {
        let canvas = NSSize(width: 42, height: 22)
        let output = NSImage(size: canvas)
        output.lockFocus()
        defer { output.unlockFocus() }

        let animatedPhase = reduceMotion ? 0 : phase
        let bounce = CGFloat(sin(animatedPhase * .pi * 2)) * amplitude(for: state)
        let squash = reduceMotion ? 1 : 1 + CGFloat(cos(animatedPhase * .pi * 2)) * 0.05
        let tilt = reduceMotion ? 0 : tiltDegrees(for: state)

        NSColor.black.withAlphaComponent(0.22).setFill()
        NSBezierPath(ovalIn: NSRect(x: 8, y: 1, width: 27, height: 3)).fill()

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: canvas.width / 2, yBy: canvas.height / 2 + bounce)
        transform.rotate(byDegrees: tilt)
        transform.scaleX(by: 1 / squash, yBy: squash)
        transform.translateX(by: -canvas.width / 2, yBy: -canvas.height / 2)
        transform.concat()

        if let source {
            let target = aspectFitRect(for: source.size, in: NSRect(x: 4, y: 3, width: 34, height: 18))
            source.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            drawDefaultCat()
        }
        NSGraphicsContext.restoreGraphicsState()

        drawOverlay(for: state)
        output.isTemplate = false
        return output
    }

    private static func amplitude(for state: PetState) -> CGFloat {
        switch state {
        case .resting: 0.4
        case .normal: 1.1
        case .running: 1.7
        case .sweating, .onFire: 2.1
        }
    }

    private static func tiltDegrees(for state: PetState) -> CGFloat {
        switch state {
        case .resting, .normal: 0
        case .running: -5
        case .sweating: -8
        case .onFire: -11
        }
    }

    private static func aspectFitRect(for size: NSSize, in bounds: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(
            x: bounds.midX - fitted.width / 2,
            y: bounds.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private static func drawDefaultCat() {
        NSColor.systemOrange.setFill()
        NSBezierPath(roundedRect: NSRect(x: 9, y: 5, width: 25, height: 12), xRadius: 5, yRadius: 5).fill()
        NSBezierPath(ovalIn: NSRect(x: 27, y: 8, width: 11, height: 10)).fill()

        let leftEar = NSBezierPath()
        leftEar.move(to: NSPoint(x: 29, y: 16))
        leftEar.line(to: NSPoint(x: 31, y: 21))
        leftEar.line(to: NSPoint(x: 34, y: 16))
        leftEar.close()
        leftEar.fill()

        NSColor.labelColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 31, y: 13, width: 1.6, height: 1.6)).fill()
        NSBezierPath(ovalIn: NSRect(x: 35, y: 13, width: 1.6, height: 1.6)).fill()

        NSColor.systemOrange.setStroke()
        let tail = NSBezierPath()
        tail.lineWidth = 2.4
        tail.move(to: NSPoint(x: 10, y: 11))
        tail.curve(to: NSPoint(x: 4, y: 17), controlPoint1: NSPoint(x: 5, y: 8), controlPoint2: NSPoint(x: 3, y: 12))
        tail.stroke()
    }

    private static func drawOverlay(for state: PetState) {
        switch state {
        case .sweating:
            NSColor.systemBlue.setFill()
            NSBezierPath(ovalIn: NSRect(x: 37, y: 14, width: 3, height: 5)).fill()
        case .onFire:
            NSColor.systemOrange.setFill()
            let flame = NSBezierPath()
            flame.move(to: NSPoint(x: 4, y: 3))
            flame.curve(to: NSPoint(x: 8, y: 19), controlPoint1: NSPoint(x: 0, y: 9), controlPoint2: NSPoint(x: 8, y: 12))
            flame.curve(to: NSPoint(x: 12, y: 3), controlPoint1: NSPoint(x: 16, y: 11), controlPoint2: NSPoint(x: 15, y: 5))
            flame.close()
            flame.fill()
        default:
            break
        }
    }
}
