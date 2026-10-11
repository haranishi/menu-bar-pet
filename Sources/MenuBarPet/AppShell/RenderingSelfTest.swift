import AppKit
import MenuBarPetCore

@MainActor
enum RenderingSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            print("\(condition ? "PASS" : "FAIL"): \(name)")
            if !condition { failures += 1 }
        }
        func pet(_ phase: Double = 0, dark: Bool = false, state: PetState = .running) -> NSImage {
            PetRenderer.render(character: .shibaInu, state: state, phase: phase,
                isDarkAppearance: dark, reduceMotion: false)
        }
        let first = pet()
        check(first === pet(1), "Loop seam reuses the same pose")
        let output = MenuBarComposer.compose(pet: first, rows: ["Claude 23 41"], isDark: false)
        check(output === MenuBarComposer.compose(pet: first, rows: ["Claude 23 41"], isDark: false),
            "Unchanged pose and text reuse the composed image")
        let changed = MenuBarComposer.compose(pet: first, rows: ["Claude 24 41"], isDark: false)
        check(output !== changed, "Usage changes invalidate the composition")
        check(first !== pet(dark: true), "Appearance changes invalidate the pose")
        check(first !== pet(state: .resting), "State changes invalidate the pose")
        for index in 0..<2000 {
            autoreleasepool {
                let image = pet(Double(index) / 2000)
                _ = MenuBarComposer.compose(pet: image, rows: ["Claude 24 41"], isDark: false)
            }
        }
        check(PetRenderer.cachedFrameCount <= 96 && MenuBarComposer.cachedImageCount <= 96,
            "Long runs keep both caches bounded")
        for index in 0..<1000 {
            autoreleasepool {
                _ = PetRenderer.render(character: .hamsterWheel, state: .running,
                    phase: Double(index) / 1000, wheelPhase: Double(index) / 1300,
                    isDarkAppearance: false, reduceMotion: false)
            }
        }
        check(PetRenderer.cachedFrameCount <= 120, "Independent wheel and body caches stay bounded")
        let red = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let blue = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.blue.setFill(); rect.fill(); return true
        }
        func custom(_ image: NSImage) -> NSImage {
            PetRenderer.render(character: .custom, state: .running, phase: 0,
                isDarkAppearance: false, reduceMotion: false, customFrames: [image, image])
        }
        check(MenuBarComposer.pngData(custom(red)) != MenuBarComposer.pngData(custom(blue)),
            "Replacing custom frames updates the image")
        print("Rendering self-test: \(8 - failures)/8 passed")
        return failures == 0
    }
}
