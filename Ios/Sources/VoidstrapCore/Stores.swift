import Foundation

enum JSONFile {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Log.write("JSONFile::load", "Could not read \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            Paths.ensure(url.deletingLastPathComponent())
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            Log.write("JSONFile::save", "Could not save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

public enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, dark, light, voidstrap, ultra_gray, berry, blue, cyan, green, orange, pink, purple, red, yellow
    public var id: String { rawValue }
    public var named: NamedTheme? { NamedTheme.all.first { $0.id == rawValue } }
    public var title: String {
        switch self {
        case .system: return "Follow system"
        case .dark: return "Dark"
        case .light: return "Light"
        default: return named?.title ?? rawValue
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var theme: AppTheme = .system
    public var githubToken: String = ""
    public var keepOriginalIpa: Bool = true
    public var language: String = "en"
    public var background: Bool = false
    public var backgroundDim: Int = 55

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = (try? c.decode(AppTheme.self, forKey: .theme)) ?? .system
        githubToken = (try? c.decode(String.self, forKey: .githubToken)) ?? ""
        keepOriginalIpa = (try? c.decode(Bool.self, forKey: .keepOriginalIpa)) ?? true
        language = (try? c.decode(String.self, forKey: .language)) ?? "en"
        background = (try? c.decode(Bool.self, forKey: .background)) ?? false
        backgroundDim = (try? c.decode(Int.self, forKey: .backgroundDim)) ?? 55
    }

    public static func load() -> AppSettings { JSONFile.load(AppSettings.self, from: Paths.settings) ?? AppSettings() }
    public func save() { JSONFile.save(self, to: Paths.settings) }
}

public struct ModPack: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var file: String
    public var enabled: Bool
    public var fileCount: Int
    public var added: Date

    public var url: URL { Paths.mods.appendingPathComponent(file) }
}

public enum ModStore {
    public static func load() -> [ModPack] {
        (JSONFile.load([ModPack].self, from: Paths.modIndex) ?? []).filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    public static func save(_ mods: [ModPack]) { JSONFile.save(mods, to: Paths.modIndex) }

    public static func importZip(_ source: URL) throws -> ModPack {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        Paths.ensure(Paths.mods)
        let id = UUID()
        let file = id.uuidString + ".zip"
        let dest = Paths.mods.appendingPathComponent(file)
        try FileManager.default.copyItem(at: source, to: dest)
        do {
            let files = try IpaPatcher.modFiles(dest)
            guard !files.isEmpty else { throw ZipError("This zip has no mod files.") }
            return ModPack(id: id, name: source.deletingPathExtension().lastPathComponent, file: file, enabled: true, fileCount: files.count, added: Date())
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw error
        }
    }

    public static func delete(_ mod: ModPack) {
        try? FileManager.default.removeItem(at: mod.url)
    }
}
