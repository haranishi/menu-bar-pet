import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MenuBarPetCore

struct PopoverView: View {
    @ObservedObject var model: PetViewModel
    @ObservedObject var systemMonitor: SystemMonitor
    @ObservedObject var aiUsage: AIUsageRepository
    let onVisualSettingsChanged: () -> Void
    let onQuit: () -> Void

    // 連携は初回しか使わないので、押した直後だけ結果を出して普段は静かにしておく。
    @ObservedObject var presentation: PopoverPresentation

    @State private var previewImage = NSImage(size: PetRenderer.pointSize)

    var body: some View {
        VStack(spacing: 0) {
            headerSection.padding(18)
            Picker("表示", selection: $presentation.tab) {
                Text("概要").tag(PopoverTab.overview)
                Text("設定").tag(PopoverTab.settings)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if presentation.tab == .overview { overview } else { settings }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Label("このMacに保存", systemImage: "lock")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("終了", action: onQuit).controlSize(.small)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
        }
        .font(.system(size: 13))
        .frame(width: 360, height: 560)
        .onAppear { reloadLinkTargets(); updatePreview() }
        .onChange(of: model.character) { updatePreview() }
        .onChange(of: model.state) { updatePreview() }
        .onChange(of: model.customFrameURLs) { updatePreview() }
    }

    private func updatePreview() {
        previewImage = PetRenderer.preview(character: model.character, state: model.state,
            isDarkAppearance: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
            customFrames: model.customFrameURLs.compactMap { NSImage(contentsOf: $0) })
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(nsImage: previewImage)
                .resizable().interpolation(.high).frame(width: 63, height: 33)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("メニューバーペット").font(.system(size: 15, weight: .semibold))
                Text(model.isPaused ? "一時停止中" : "\(model.character.displayName) · \(model.state.displayName)")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(action: { model.togglePaused(); onVisualSettingsChanged() }) {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: 22, height: 22)
            }
            .accessibilityLabel(model.isPaused ? "再開" : "一時停止")
            .keyboardShortcut(.space, modifiers: [])
            .help(model.isPaused ? "再開" : "一時停止")
        }
    }

    private var metricPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("動きに反映する指標").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Picker("動かす指標", selection: Binding(get: { model.metricSource }, set: {
                model.setMetricSource($0); onVisualSettingsChanged()
            })) {
                ForEach(MetricSource.allCases) { Text($0.displayName).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
        }
    }

    private var overview: some View {
        Group {
            metricPicker
            card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.metricSource == .cpu ? "CPU 使用率" : "AI 使用率")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        if model.debugOverrideUsage != nil {
                            Text("動作確認中").font(.system(size: 11)).foregroundStyle(.orange)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(headlinePercentage.map { String($0) } ?? "—")
                            .font(.system(size: 38, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("%").font(.system(size: 18)).foregroundStyle(.secondary)
                        Spacer()
                        if model.metricSource == .aiUsage, let percentage = headlinePercentage {
                            Text("残り \(100 - percentage)%").font(.system(size: 13, weight: .medium))
                        }
                    }
                    Text(headlineDetail).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("AIの使用枠", symbol: "chart.bar")
                if aiUsage.snapshots.isEmpty {
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("まだ使用量が届いていません").fontWeight(.medium)
                            Text("Codexは利用すると自動で表示されます。Claude Codeは設定から連携できます。")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("連携設定を開く") { presentation.tab = .settings; presentation.showsLink = true }
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(AIUsageProvider.allCases.filter { model.aiUsageProviders.contains($0) }) { provider in
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(aiUsage.snapshots.filter { $0.provider == provider }, id: \.sourcePath) { snapshot in
                                    snapshotBlock(snapshot)
                                }
                                if !aiUsage.snapshots.contains(where: { $0.provider == provider }) {
                                    card {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(provider.shortName).fontWeight(.semibold)
                                            Text("まだデータがありません").font(.system(size: 12)).foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                            .frame(width: model.aiUsageProviders.count == 1 ? 324 : 157, alignment: .topLeading)
                        }
                    }
                }
                if let refreshed = aiUsage.lastRefreshedAt {
                    Text("更新 \(clockText(refreshed))").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            card { systemSection }
        }
    }

    private var headlinePercentage: Int? {
        if let value = model.debugOverrideUsage { return Int(value.rounded()) }
        if model.metricSource == .cpu { return Int(model.cpuUsage.rounded()) }
        guard let binding = model.aiBindingWindow else { return nil }
        return Int(AIUsageAggregator.effectiveUsedPercentage(binding.window, now: Date()).rounded())
    }

    private var headlineDetail: String {
        if model.debugOverrideUsage != nil { return "設定の「動作を確認」で指定した使用率です" }
        guard model.metricSource == .aiUsage else { return "CPUの使用率に合わせて走ります" }
        guard let binding = model.aiBindingWindow else { return "データが届くと走り始めます" }
        return "\(binding.snapshot.provider.shortName) · \(binding.window.label) の使用率を反映"
    }

    private var settings: some View {
        Group {
            card {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("ペット", symbol: "pawprint")
                    Picker("キャラ", selection: Binding(get: { model.character }, set: {
                        model.setCharacter($0); onVisualSettingsChanged()
                    })) {
                        ForEach(model.availableCharacters) { Text($0.displayName).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    Button("自作ランナーを登録…", action: presentRunnerImporter)
                    if !model.customFrameURLs.isEmpty {
                        HStack {
                            Text("\(model.customFrameURLs.count)枚のコマ画像").foregroundStyle(.secondary)
                            Spacer()
                            Button("削除") { model.deleteCustomRunner(); onVisualSettingsChanged() }
                        }
                    }
                    if let message = model.statusMessage {
                        Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            card {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("メニューバー", symbol: "menubar.rectangle")
                    Toggle("メニューバーに数値を表示", isOn: Binding(get: { model.showsMenuBarReadout }, set: {
                        model.setShowsMenuBarReadout($0); onVisualSettingsChanged()
                    }))
                    Text("表示・動きに使うAI").foregroundStyle(.secondary)
                    ForEach(AIUsageProvider.allCases) { provider in
                        Toggle(provider.displayName, isOn: Binding(
                            get: { model.aiUsageProviders.contains(provider) },
                            set: { model.setProvider(provider, enabled: $0) }
                        )).disabled(!model.canDisableProvider(provider))
                    }
                    Text("AIの数値は使用率です。短い枠・長い枠の順に表示します。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            card {
                DisclosureGroup("AIの連携", isExpanded: $presentation.showsLink) {
                    linkSection.padding(.top, 10)
                }
            }
            card {
                DisclosureGroup("動作を確認", isExpanded: $presentation.showsDemo) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("負荷テストモード", isOn: Binding(
                            get: { model.debugOverrideUsage != nil },
                            set: { model.debugOverrideUsage = $0 ? 50 : nil }
                        ))
                        if model.debugOverrideUsage != nil {
                            HStack {
                                Slider(value: Binding(get: { model.debugOverrideUsage ?? 50 },
                                    set: { model.debugOverrideUsage = $0 }), in: 0...100, step: 1)
                                    .accessibilityLabel("疑似使用率")
                                Text("\(Int((model.debugOverrideUsage ?? 50).rounded()))%")
                                    .monospacedDigit().frame(width: 38, alignment: .trailing)
                            }
                        }
                        Text("Macに負荷をかけずに、走る速さを確認できます。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 10)
                }
            }
        }
    }

    private func snapshotBlock(_ snapshot: AIUsageSnapshot) -> some View {
        let now = Date()
        return card {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.provider.shortName).font(.system(size: 14, weight: .semibold))
                    Text(snapshot.profileName).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                ForEach(Array(AIUsageAggregator.drivingWindows(snapshot, now: now).enumerated()), id: \.offset) { _, window in
                    let used = AIUsageAggregator.effectiveUsedPercentage(window, now: now)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(window.label).font(.system(size: 12))
                            Spacer(minLength: 2)
                            Text("\(Int(used.rounded()))%").fontWeight(.medium).monospacedDigit()
                        }
                        ProgressView(value: used, total: 100)
                            .tint(used >= 90 ? .orange : .accentColor)
                            .accessibilityLabel("\(snapshot.provider.shortName) \(window.label)")
                        let resets = AIUsageAggregator.formatResetsAt(window.resetsAt, now: now)
                        if !resets.isEmpty {
                            Text(resets).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                if let note = snapshot.note {
                    let notice = usageNotice(snapshot, fallback: note, now: now)
                    Label(notice, systemImage: "exclamationmark.circle")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold))
    }

    private func usageNotice(_ snapshot: AIUsageSnapshot, fallback: String, now: Date) -> String {
        guard let type = snapshot.rateLimitReachedType else { return fallback }
        let message = type.contains("credits") ? "クレジット切れ" : "利用上限に達しました"
        return AIUsageAggregator.reachedLimitWindow(snapshot, now: now) == nil
            ? "前回: \(message)" : message
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, alignment: .leading).padding(13)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5))
    }

    // MARK: - 連携

    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if presentation.linkTargets.isEmpty {
                Text("Claude Code の設定ホームが見つかりません。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(presentation.linkTargets) { target in
                HStack {
                    Text("\(target.profileName) ｜ \(target.statusText)")
                        .font(.system(size: 12))
                    Spacer()
                    if !target.isInstalled || target.needsRelink {
                        Button(target.needsRelink ? "貼り直す…" : "連携する…") { confirmLink(target) }
                    }
                    if target.isInstalled {
                        Button("解除") { confirmUnlink(target) }
                    }
                }
            }
            Text("Codex は設定不要（セッションログを読み取り）")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if let linkMessage = presentation.linkMessage {
                Text(linkMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func reloadLinkTargets() {
        presentation.linkTargets = ClaudeLinkService.targets()
    }

    private func confirmLink(_ target: ClaudeLinkTarget) {
        let alert = NSAlert()
        alert.messageText = "\(target.profileName) と連携しますか？"
        alert.informativeText = """
            \(target.settingsURL.path) の statusLine をこのアプリに向けます。
            元の設定は同じ場所へ settings.json.menubarpet-backup-<日時> として控えを残します。
            既に statusLine を使っている場合は、そのコマンドを引き継いで表示を維持します。
            """
        alert.addButton(withTitle: "連携する")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        run(onSuccess: "\(target.profileName) と連携しました。次の応答から反映されます。") {
            try ClaudeLinkService.link(target)
        }
    }

    private func confirmUnlink(_ target: ClaudeLinkTarget) {
        let alert = NSAlert()
        alert.messageText = "\(target.profileName) の連携を解除しますか？"
        alert.informativeText = """
            \(target.settingsURL.path) の statusLine を元に戻します（引き継いだコマンドがあればそれに戻します）。
            変更前の控えを settings.json.menubarpet-backup-<日時> として残します。
            """
        alert.addButton(withTitle: "解除する")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        run(onSuccess: "\(target.profileName) の連携を解除しました。") {
            try ClaudeLinkService.unlink(target)
        }
    }

    private func run(onSuccess message: String, _ work: () throws -> Void) {
        do {
            try work()
            presentation.linkMessage = message
        } catch {
            presentation.linkMessage = error.localizedDescription
        }
        reloadLinkTargets()
    }

    // MARK: - システム

    private var systemSection: some View {
        let snapshot = systemMonitor.snapshot
        return VStack(alignment: .leading, spacing: 4) {
            Text("システム").font(.headline)
            systemRow("メモリ", "\(snapshot.memoryUsagePercentage)%")
            systemRow(
                "ストレージ",
                "\(SystemFormatting.formatAvailableBytes(snapshot.availableStorageBytes)) 空き"
            )
            if let battery = snapshot.battery {
                systemRow(
                    "バッテリー",
                    "\(battery.percentage)%\(battery.isConnectedToPower ? "・電源接続" : "")"
                )
            }
            systemRow(
                "ネットワーク",
                "↓\(SystemFormatting.formatBytesPerSecond(snapshot.downloadBytesPerSecond))"
                    + "  ↑\(SystemFormatting.formatBytesPerSecond(snapshot.uploadBytesPerSecond))"
            )
        }
    }

    private func systemRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
        }
        .accessibilityElement(children: .combine)
    }

    private func clockText(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private func presentRunnerImporter() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png]
        panel.prompt = "登録"
        panel.message = """
            コマ画像のPNGを2〜24枚選んでください（ファイル名の昇順がコマ順）。
            透過PNG推奨・権利を持つ画像のみ・このMac内だけで処理します。
            """
        guard panel.runModal() == .OK else { return }
        model.registerCustomRunner(from: panel.urls)
        onVisualSettingsChanged()
    }
}

enum PopoverTab: String { case overview, settings }

@MainActor
final class PopoverPresentation: ObservableObject {
    @Published var tab: PopoverTab = .overview
    @Published var showsLink = false
    @Published var showsDemo = false
    @Published var linkTargets: [ClaudeLinkTarget] = []
    @Published var linkMessage: String?
}

@MainActor
final class PopoverVisibility: ObservableObject {
    @Published var isVisible = false
}

/// Unmount the observation-heavy view while the popover is hidden.
struct PopoverMountGate: View {
    @ObservedObject var visibility: PopoverVisibility
    let model: PetViewModel
    let systemMonitor: SystemMonitor
    let aiUsage: AIUsageRepository
    let presentation: PopoverPresentation
    let onVisualSettingsChanged: () -> Void
    let onQuit: () -> Void

    var body: some View {
        if visibility.isVisible {
            PopoverView(
                model: model, systemMonitor: systemMonitor, aiUsage: aiUsage,
                onVisualSettingsChanged: onVisualSettingsChanged,
                onQuit: onQuit, presentation: presentation
            )
        } else {
            Color.clear.frame(width: 360, height: 560)
        }
    }
}
