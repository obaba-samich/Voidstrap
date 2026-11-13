import SwiftUI
import VoidstrapCore

struct RobloxSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Page(title: "Roblox Settings", subtitle: "Roblox's own settings, set every time you launch Roblox from Voidstrap.") {
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

            SectionTitle(text: "Comfort")
            Card {
                toggle("figure.walk.motion", "Reduced motion", "Less camera and interface movement", model.robloxSettings.reducedMotion ?? false) {
                    model.robloxSettings.reducedMotion = $0
                }
            }

            Text(loc: "Roblox on iOS ignores FastFlags, so Voidstrap changes Roblox's own settings instead. Open Roblox once before your first launch from here.")
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
        Row(symbol: symbol, title: title, detail: detail) {
            Menu {
                ForEach(Array(labels.enumerated()), id: \.offset) { item in
                    Button { change(item.offset) } label: {
                        if item.offset == selected { Label(Loc.t(item.element), systemImage: "checkmark") } else { Text(Loc.t(item.element)) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(Loc.t(labels[selected])).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Palette.primary)
            }
            .accessibilityLabel(Loc.t(title))
        }
    }
}
