import Foundation

public struct RobloxSettings: Codable, Equatable, Sendable {
    public var framerateCap: Int?
    public var performanceStats: Bool?
    public var reducedMotion: Bool?
    public var masterVolume: Double?
    public var cameraInverted: Bool?
    public var vignette: Bool?
    public var textSize: Int?
    public var menuTransparency: Double?
    public var haptics: Double?

    public static let framerateCaps = [-1, 30, 60, 120]
    public static let textSizes = 1...4
    static let prefix = "GlobalBasicSettings_"
    nonisolated(unsafe) static var lastReport = ""

    public init() {}

    public static func load() -> RobloxSettings { JSONFile.load(RobloxSettings.self, from: Paths.robloxSettings) ?? RobloxSettings() }
    public func save() { JSONFile.save(self, to: Paths.robloxSettings) }

    var values: [(String, String)] {
        var out: [(String, String)] = []
        if let framerateCap { out.append(("FramerateCap", String(framerateCap))) }
        if let performanceStats { out.append(("PerformanceStatsVisible", performanceStats ? "true" : "false")) }
        if let reducedMotion { out.append(("ReducedMotion", reducedMotion ? "true" : "false")) }
        if let masterVolume { out.append(("MasterVolume", number(masterVolume))) }
        if let cameraInverted { out.append(("CameraYInverted", cameraInverted ? "true" : "false")) }
        if let vignette { out.append(("VignetteEnabled", vignette ? "true" : "false")) }
        if let textSize { out.append(("PreferredTextSize", String(textSize))) }
        if let menuTransparency { out.append(("PreferredTransparency", number(menuTransparency))) }
        if let haptics { out.append(("HapticStrength", number(haptics))) }
        return out
    }

    public var count: Int { values.count }

    func number(_ value: Double) -> String { String(format: "%g", min(max(value, 0), 1)) }

    static func file(_ container: URL) -> URL? {
        let support = container.appendingPathComponent("Library/Application Support", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: support.path)) ?? []
        func number(_ name: String) -> Int { Int(name.dropFirst(prefix.count).dropLast(4)) ?? 0 }
        let best = names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".xml") }.max { number($0) < number($1) }
        return best.map { support.appendingPathComponent($0) }
    }

    static func set(_ name: String, _ value: String, in text: inout String) -> Bool {
        guard let start = text.range(of: "name=\"\(name)\">"),
              let end = text.range(of: "<", range: start.upperBound..<text.endIndex) else { return false }
        text.replaceSubrange(start.upperBound..<end.lowerBound, with: value)
        return true
    }

    @discardableResult
    public static func apply(_ settings: RobloxSettings) -> Int {
        var written = 0
        var notes: [String] = []
        for container in RobloxData.containers {
            guard let file = file(container) else {
                notes.append("\(container.lastPathComponent): no settings file yet")
                continue
            }
            do {
                let original = try String(contentsOf: file, encoding: .utf8)
                var text = original
                let missing = settings.values.filter { !set($0.0, $0.1, in: &text) }.map(\.0)
                if text != original { try text.write(to: file, atomically: true, encoding: .utf8) }
                written += 1
                notes.append("\(container.lastPathComponent): \(settings.count - missing.count) set" + (missing.isEmpty ? "" : ", not in file: \(missing.joined(separator: " "))"))
            } catch {
                Log.error("RobloxSettings::apply", error)
            }
        }
        let report = notes.isEmpty ? "No Roblox data folder found" : notes.joined(separator: ", ")
        if report != lastReport {
            lastReport = report
            Log.write("RobloxSettings::apply", report)
        }
        return written
    }
}
