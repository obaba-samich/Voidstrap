import Foundation

public enum RobloxData {
    static let bundleId = "com.roblox.robloxmobile"
    static let markers = ["Library/Preferences/\(bundleId).plist", "Library/Caches/\(bundleId)"]
    static let leftover = "Library/Application Support/ClientSettings/ClientAppSettings.json"

    static var groups: [String] {
        var out = entitledGroups + ["group.com.SideStore.SideStore", "group.com.rileytestut.AltStore", "group.com.kdt.livecontainer", "group.com.livecontainer"]
        for key in ["LCAppGroupID", "ALTAppGroups", "AppGroups"] {
            if let one = Bundle.main.object(forInfoDictionaryKey: key) as? String { out.append(one) }
            if let many = Bundle.main.object(forInfoDictionaryKey: key) as? [String] { out += many }
        }
        return out
    }

    static var entitledGroups: [String] {
        typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
        typealias Copy = @convention(c) (AnyObject, CFString, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<AnyObject>?
        guard let lib = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW),
              let createSym = dlsym(lib, "SecTaskCreateFromSelf"),
              let copySym = dlsym(lib, "SecTaskCopyValueForEntitlement") else { return [] }
        let create = unsafeBitCast(createSym, to: Create.self)
        let copy = unsafeBitCast(copySym, to: Copy.self)
        guard let task = create(nil)?.takeRetainedValue(),
              let value = copy(task, "com.apple.security.application-groups" as CFString, nil)?.takeRetainedValue() else { return [] }
        return value as? [String] ?? []
    }

    static var roots: [URL] {
        var out: [URL] = []
        let path = Paths.documents.standardizedFileURL.path
        if let range = path.range(of: "/Data/Application/", options: .backwards) {
            out.append(URL(fileURLWithPath: String(path[..<range.lowerBound]), isDirectory: true))
        }
        let shared = Paths.shared.standardizedFileURL
        if !out.contains(where: { $0.path == shared.path }) { out.append(shared) }
        for group in groups {
            guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { continue }
            let lc = url.appendingPathComponent("LiveContainer", isDirectory: true).standardizedFileURL
            if FileManager.default.fileExists(atPath: lc.path), !out.contains(where: { $0.path == lc.path }) { out.append(lc) }
        }
        return out
    }

    static func plist(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    static func registered(_ root: URL) -> [URL] {
        let fm = FileManager.default
        let apps = root.appendingPathComponent("Applications", isDirectory: true)
        var out: [URL] = []
        for app in (try? fm.contentsOfDirectory(at: apps, includingPropertiesForKeys: nil)) ?? [] {
            guard (plist(app.appendingPathComponent("Info.plist"))?["CFBundleIdentifier"] as? String)?.lowercased() == bundleId else { continue }
            let info = plist(app.appendingPathComponent("LCAppInfo.plist")) ?? [:]
            var ids: [String] = []
            if let id = info["LCDataUUID"] as? String { ids.append(id) }
            for container in info["LCContainers"] as? [[String: Any]] ?? [] {
                if let id = container["folderName"] as? String { ids.append(id) }
            }
            for id in ids {
                out.append(root.appendingPathComponent("Data/Application/\(id)", isDirectory: true))
            }
        }
        return out
    }

    static func scanned(_ root: URL) -> [URL] {
        let fm = FileManager.default
        let data = root.appendingPathComponent("Data/Application", isDirectory: true)
        let items = (try? fm.contentsOfDirectory(at: data, includingPropertiesForKeys: nil)) ?? []
        return items.filter { dir in markers.contains { fm.fileExists(atPath: dir.appendingPathComponent($0).path) } }
    }

    static let bundleFiles = ["ClientSettings/ClientAppSettings.json", "Frameworks/RobloxLib.framework/ClientSettings/ClientAppSettings.json"]

    static var bundles: [URL] {
        roots.flatMap { root -> [URL] in
            let apps = root.appendingPathComponent("Applications", isDirectory: true)
            return ((try? FileManager.default.contentsOfDirectory(at: apps, includingPropertiesForKeys: nil)) ?? []).filter {
                (plist($0.appendingPathComponent("Info.plist"))?["CFBundleIdentifier"] as? String)?.lowercased() == bundleId
            }
        }
    }

    public static var containers: [URL] {
        guard Paths.isLiveContainer else { return [] }
        var seen = Set<String>()
        var out: [URL] = []
        for root in roots {
            for dir in registered(root) + scanned(root) where seen.insert(dir.standardizedFileURL.path).inserted {
                out.append(dir)
            }
        }
        return out
    }

    public static func removeLeftovers() {
        let fm = FileManager.default
        for container in containers {
            let file = container.appendingPathComponent(leftover)
            chflags(file.path, 0)
            try? fm.removeItem(at: file)
        }
        for bundle in bundles {
            for rel in bundleFiles { try? fm.removeItem(at: bundle.appendingPathComponent(rel)) }
        }
    }
}
