import SwiftUI
import VoidstrapCore

struct RobloxSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Page(title: "Roblox Settings", subtitle: "Roblox's own settings, saved to Roblox as soon as you change them.") {
            SectionTitle(text: "Performance")
            Card {
                choice("speedometer", "Frame rate limit", "Above 60 needs a ProMotion display", ["Default", "30", "60", "120"],
                       RobloxSettings.framerateCaps.firstIndex(of: model.robloxSettings.framerateCap ?? -1) ?? 0) {
                    model.robloxSettings.framerateCap = RobloxSettings.framerateCaps[$0]
                }
                RowDivider()
                toggle("gauge", "Performance stats", "Shows Roblox's frame rate and memory panel", model.robloxSettings.performanceStats ?? false) {
                    model.robloxSettings.performanceStats = $0
                }
            }

            SectionTitle(text: "Display")
            Card {
                choice("textformat.size", "Text size", "Size of Roblox menus and chat", ["Medium", "Large", "Larger", "Largest"],
                       (model.robloxSettings.textSize ?? 1) - RobloxSettings.textSizes.lowerBound) {
                    model.robloxSettings.textSize = RobloxSettings.textSizes.lowerBound + $0
                }
                RowDivider()
                Row(symbol: "square.on.square", title: "Menu transparency", detail: "How see through Roblox menus are") { EmptyView() }
                slider(model.robloxSettings.menuTransparency ?? 1) { model.robloxSettings.menuTransparency = $0 }
                RowDivider()
                toggle("circle.dashed", "Vignette", "Darkens the screen edges in first person", model.robloxSettings.vignette ?? true) {
                    model.robloxSettings.vignette = $0
                }
            }

            SectionTitle(text: "Controls and sound")
            Card {
                toggle("arrow.up.arrow.down", "Invert camera", "Flips up and down camera movement", model.robloxSettings.cameraInverted ?? false) {
                    model.robloxSettings.cameraInverted = $0
                }
                RowDivider()
                Row(symbol: "speaker.wave.2", title: "Volume", detail: "Roblox master volume") { EmptyView() }
                slider(model.robloxSettings.masterVolume ?? 1) { model.robloxSettings.masterVolume = $0 }
                RowDivider()
                Row(symbol: "iphone.radiowaves.left.and.right", title: "Haptics", detail: "Vibration strength") { EmptyView() }
                slider(model.robloxSettings.haptics ?? 1) { model.robloxSettings.haptics = $0 }
            }

            SectionTitle(text: "Comfort")
            Card {
                toggle("figure.walk.motion", "Reduced motion", "Less camera and interface movement", model.robloxSettings.reducedMotion ?? false) {
                    model.robloxSettings.reducedMotion = $0
                }
            }

            Text(loc: "Roblox on iOS ignores FastFlags, so Voidstrap changes Roblox's own settings instead. Open Roblox once first so its settings file exists, and close Roblox before changing settings here.")
                .font(.system(size: 13))
                .foregroundColor(Palette.textSecondary)
                .padding(.horizontal, 4)
        }
    }

    private func toggle(_ symbol: String, _ title: String, _ detail: String, _ value: Bool, _ change: @escaping (Bool) -> Void) -> some View {
        Row(symbol: symbol, title: title, detail: detail) {
            Toggle("", isOn: Binding(get: { value }, set: change)).labelsHidden().accessibilityLabel(Loc.t(title))
        }
    }

    private func choice(_ symbol: String, _ title: String, _ detail: String, _ labels: [String], _ selected: Int, _ change: @escaping (Int) -> Void) -> some View {
        let index = min(max(selected, 0), labels.count - 1)
        return Row(symbol: symbol, title: title, detail: detail) {
            Picker(Loc.t(title), selection: Binding(get: { index }, set: change)) {
                ForEach(Array(labels.enumerated()), id: \.offset) { item in
                    Text(Loc.t(item.element)).tag(item.offset)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(Palette.primary)
        }
    }

    private func slider(_ value: Double, _ change: @escaping (Double) -> Void) -> some View {
        SettingSlider(value: value, change: change)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }
}

struct SettingSlider: View {
    let value: Double
    let change: (Double) -> Void
    @State private var draft: Double?

    var body: some View {
        HStack(spacing: 10) {
            Text(loc: "Low").font(.system(size: 13)).foregroundColor(Palette.textTertiary)
            Slider(value: Binding(get: { draft ?? value }, set: { draft = $0 }), in: 0...1, step: 0.1) { editing in
                if !editing, let draft {
                    change(draft)
                    self.draft = nil
                }
            }
            Text(loc: "High").font(.system(size: 13)).foregroundColor(Palette.textTertiary)
        }
    }
}
