import AppKit
import ApplicationServices

enum SmokeError: Error { case failed(String) }

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}
func descendants(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 12 else { return [] }
    let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    return [element] + children.flatMap { descendants($0, depth: depth + 1) }
}
func label(_ element: AXUIElement) -> String {
    attribute(element, kAXDescriptionAttribute) as? String
        ?? attribute(element, kAXTitleAttribute) as? String ?? ""
}
func role(_ element: AXUIElement) -> String { attribute(element, kAXRoleAttribute) as? String ?? "" }
func value(_ element: AXUIElement) -> Int { (attribute(element, kAXValueAttribute) as? NSNumber)?.intValue ?? -1 }
func settle(_ seconds: Double = 0.3) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
func press(_ element: AXUIElement) throws {
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
        throw SmokeError.failed("Could not press \(label(element))")
    }
    settle()
}
func check(_ success: Bool, _ message: String) throws {
    guard success else { throw SmokeError.failed(message) }
    print("PASS: \(message)")
    fflush(stdout)
}

do {
    guard AXIsProcessTrusted(),
          let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.hara.MenuBarPet").first
    else { throw SmokeError.failed("Running MenuBarPet and existing accessibility permission are required") }
    let app = AXUIElementCreateApplication(running.processIdentifier)
    func menuItem() throws -> AXUIElement {
        guard let extras = attribute(app, "AXExtrasMenuBar"), CFGetTypeID(extras) == AXUIElementGetTypeID(),
              let item = descendants(unsafeBitCast(extras, to: AXUIElement.self)).first(where: { role($0) == "AXMenuBarItem" })
        else { throw SmokeError.failed("Menu bar item missing") }
        return item
    }
    func popover() -> AXUIElement? {
        guard let item = try? menuItem() else { return nil }
        return descendants(item).first { role($0) == "AXPopover" }
    }
    func ensureOpen() throws {
        if popover() == nil {
            running.activate(options: [.activateAllWindows])
            try press(menuItem())
            settle(0.8)
        }
    }
    func control(_ name: String, _ expectedRole: String) throws -> AXUIElement {
        try ensureOpen()
        let page = ["CPU", "AI使用率"].contains(name) ? "概要" : "設定"
        if !["再開", "一時停止", "終了"].contains(name), let popover = popover(),
           let tab = descendants(popover).first(where: { label($0) == page && role($0) == "AXRadioButton" }), value(tab) != 1 {
            try press(tab)
        }
        for _ in 0..<5 {
            if let popover = popover(),
               let result = descendants(popover).first(where: { label($0) == name && role($0) == expectedRole }) {
                return result
            }
            settle(0.1)
        }
        throw SmokeError.failed("Control missing: \(name)")
    }
    try ensureOpen()
    try check(popover() != nil, "Click opens the popover")
    let originalTab = descendants(popover()!).first { label($0) == "概要" && value($0) == 1 } == nil ? "設定" : "概要"
    let originalCPU = value(try control("CPU", "AXRadioButton")) == 1
    let originalCharacter = ["柴犬", "ハムスター", "自作ランナー"].first { name in
        (try? control(name, "AXRadioButton")).map { value($0) == 1 } ?? false
    } ?? "柴犬"
    let originalReadout = value(try control("メニューバーに数値を表示", "AXCheckBox"))
    let originalPaused = label(try menuItem()).contains("一時停止中")
    let preferences = "com.hara.MenuBarPet" as CFString
    let originalSettings = CFPreferencesCopyAppValue("app-settings-v1" as CFString, preferences)
    defer {
        // Restore settings through controls so the running model and disk agree.
        try? press(try control(originalCPU ? "CPU" : "AI使用率", "AXRadioButton"))
        try? press(try control(originalCharacter, "AXRadioButton"))
        if let readout = try? control("メニューバーに数値を表示", "AXCheckBox"), value(readout) != originalReadout {
            try? press(readout)
        }
        if (try? menuItem()).map({ label($0).contains("一時停止中") }) != originalPaused {
            try? press(try control(originalPaused ? "一時停止" : "再開", "AXButton"))
        }
        CFPreferencesSetAppValue("app-settings-v1" as CFString, originalSettings, preferences)
        CFPreferencesAppSynchronize(preferences)
        try? press(try control(originalTab, "AXRadioButton"))
        if popover() != nil { try? press(menuItem()) }
    }
    try press(try control("CPU", "AXRadioButton"))
    try check(value(try control("CPU", "AXRadioButton")) == 1, "CPU mode selected")
    try press(try control("AI使用率", "AXRadioButton"))
    try check(value(try control("AI使用率", "AXRadioButton")) == 1, "AI mode selected")
    try press(try control("ハムスター", "AXRadioButton"))
    try check(value(try control("ハムスター", "AXRadioButton")) == 1, "Hamster selected")
    try press(try control("柴犬", "AXRadioButton"))
    try check(value(try control("柴犬", "AXRadioButton")) == 1, "Shiba selected")
    let toggle = try control("メニューバーに数値を表示", "AXCheckBox")
    if value(toggle) == 1 { try press(toggle) }
    try check(!label(try menuItem()).contains("Claude") && !label(try menuItem()).contains("Codex"), "Readout disappears when disabled")
    try press(try control("メニューバーに数値を表示", "AXCheckBox"))
    try check(label(try menuItem()).contains("Claude") || label(try menuItem()).contains("Codex"), "Readout returns when enabled")
    if label(try menuItem()).contains("一時停止中") { try press(try control("再開", "AXButton")) }
    settle(1.2)
    try check(!label(try menuItem()).contains("一時停止中"), "Animation resumes")
    running.activate(options: [.activateAllWindows])
    func sendKey(_ code: CGKeyCode) {
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)?.postToPid(running.processIdentifier)
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)?.postToPid(running.processIdentifier)
        settle(0.5)
    }
    sendKey(49)
    try check(label(try menuItem()).contains("一時停止中"), "Space pauses the animation")
    sendKey(49)
    try check(!label(try menuItem()).contains("一時停止中"), "Space resumes the animation")
    try press(try control("一時停止", "AXButton"))
    try check(label(try menuItem()).contains("一時停止中") && label(try menuItem()).contains("Claude"), "Pause keeps the readout visible")
    try press(menuItem())
    try check(popover() == nil, "Click closes the popover")
    settle(1) // AX removes the tree before the native closing animation finishes.
    try press(menuItem())
    settle(0.7)
    try check(popover() != nil, "Popover mounts again after closing")
    try check(value(try control("AI使用率", "AXRadioButton")) == 1, "Mode survives popover remount")
    if let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] {
        for window in windows where (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == running.processIdentifier {
            if let id = window[kCGWindowNumber as String] as? NSNumber,
               let bounds = window[kCGWindowBounds as String] as? [String: Any],
               (bounds["Width"] as? NSNumber)?.intValue ?? 0 > 200 {
                print("POPOVER_WINDOW_ID=\(id.uint32Value)")
            }
        }
    }
    if let flag = CommandLine.arguments.firstIndex(of: "--soak-seconds"),
       CommandLine.arguments.indices.contains(flag + 1),
       let duration = Double(CommandLine.arguments[flag + 1]), (10...600).contains(duration) {
        if label(try menuItem()).contains("一時停止中") { try press(try control("再開", "AXButton")) }
        if popover() != nil { try press(menuItem()) }
        let started = Date()
        var samples: [[String: Double]] = []
        while Date().timeIntervalSince(started) < duration {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-p", String(running.processIdentifier), "-o", "%cpu=,rss="]
            let pipe = Pipe(); process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            let values = String(decoding: data, as: UTF8.self).split(whereSeparator: { $0.isWhitespace }).compactMap { Double($0) }
            try check(values.count == 2, "App remains alive during soak")
            samples.append(["seconds": Date().timeIntervalSince(started), "cpu_percent": values[0], "rss_kib": values[1]])
            settle(min(10, max(0, duration - Date().timeIntervalSince(started))))
        }
        let report: [String: Any] = ["duration_seconds": duration, "scope": "Live app, animation active, popover closed; process ps samples", "samples": samples]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        if let outputFlag = CommandLine.arguments.firstIndex(of: "--soak-output"), CommandLine.arguments.indices.contains(outputFlag + 1) {
            try data.write(to: URL(fileURLWithPath: CommandLine.arguments[outputFlag + 1]))
        }
        print("SOAK: \(duration)s, \(samples.count) samples")
    }
    let importButton = try control("自作ランナーを登録…", "AXButton")
    let targetPID = running.processIdentifier
    // Cancel the native modal panel while AXPress waits for its action to return.
    DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
        let app = AXUIElementCreateApplication(targetPID)
        for _ in 0..<10 {
            let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
            if let cancel = windows.flatMap({ descendants($0) }).first(where: {
                role($0) == "AXButton" && ["Cancel", "キャンセル"].contains(attribute($0, kAXTitleAttribute) as? String ?? "")
            }) {
                AXUIElementPerformAction(cancel, kAXPressAction as CFString)
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }
    try press(importButton)
    settle(0.5)
    try ensureOpen()
    try check(popover() != nil, "Import cancellation returns to the controls")
    print("RESULT: GUI smoke checks passed; original settings restored on exit")
} catch {
    print("FAIL: \(error)")
    exit(1)
}
