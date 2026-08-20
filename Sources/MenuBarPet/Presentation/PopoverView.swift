import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: PetViewModel
    let onChooseImage: () -> Void
    let onVisualSettingsChanged: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.state.displayName).font(.headline)
                    Text("CPU \(Int(model.cpuUsage.rounded()))%")
                        .font(.system(.body, design: .monospaced))
                }
                Spacer()
                Button(model.isPaused ? "再開" : "一時停止") {
                    model.togglePaused()
                    onVisualSettingsChanged()
                }
            }

            Picker("感度", selection: Binding(
                get: { model.sensitivity },
                set: { model.setSensitivity($0) }
            )) {
                ForEach(Sensitivity.allCases) { sensitivity in
                    Text(sensitivity.displayName).tag(sensitivity)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button("画像を選ぶ", action: onChooseImage)
                if model.petImage != nil {
                    Button("標準に戻す") {
                        model.useStandardPet()
                        onVisualSettingsChanged()
                    }
                }
            }

            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()
            HStack {
                Label("画像・設定はこのMacだけに保存", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("終了", action: onQuit)
            }
        }
        .padding(14)
        .frame(width: 310)
    }
}
