import Foundation

/// Last place, shared by the Watch app and the complication extension.
///
/// Personal Team provisioning cannot create an App Group, and these targets
/// do not add that entitlement. The Watch app writes `watch-place.json` into
/// its own documents directory and into the complication extension's documents
/// directory. Those containers sit next to each other under the watch data
/// directory. The complication reads the file from its own documents, with no
/// extra entitlement, and does not stay on the sample city after the glance
/// has moved.
enum WatchPlaceStore {
    static let fileName = "watch-place.json"
    static let watchAppID = "cloud.janglim.jaccuweather.watchkitapp"
    static let complicationID = "cloud.janglim.jaccuweather.watchkitapp.widgets"

    static func save(_ place: WatchPlace) {
        guard let data = try? JSONEncoder().encode(place) else { return }
        for url in fileURLs() {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load() -> WatchPlace? {
        for url in fileURLs() {
            if let data = try? Data(contentsOf: url), let place = decode(data) {
                return place
            }
        }
        return nil
    }

    /// Place files this process can see: its own documents, the Watch app's
    /// documents, and the complication's documents.
    static func fileURLs() -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        func add(_ url: URL) {
            let path = url.path
            guard seen.insert(path).inserted else { return }
            urls.append(url)
        }
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            add(docs.appendingPathComponent(fileName, isDirectory: false))
        }
        for id in [watchAppID, complicationID] {
            if let container = dataContainer(identifier: id) {
                let docs = container.appendingPathComponent("Documents", isDirectory: true)
                add(docs.appendingPathComponent(fileName, isDirectory: false))
            }
        }
        return urls
    }

    /// The data container for a watch bundle id, found beside this process's
    /// own container. Returns nil when the sandbox will not list that directory.
    ///
    /// The Watch app's home is its container. Chrono's placeholder host reports
    /// the simulator data directory instead, so the search walks up until it
    /// finds `Containers/Data`.
    static func dataContainer(identifier: String) -> URL? {
        guard let dataRoot = containerDataRoot() else { return nil }
        for folder in ["Application", "PluginKitPlugin"] {
            let root = dataRoot.appendingPathComponent(folder, isDirectory: true)
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries {
                let meta = entry.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                guard let data = try? Data(contentsOf: meta),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                      plist["MCMMetadataIdentifier"] as? String == identifier else { continue }
                return entry
            }
        }
        return nil
    }

    static func containerDataRoot() -> URL? {
        let fileManager = FileManager.default
        var url = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        for _ in 0..<8 {
            let containers = url.appendingPathComponent("Containers/Data", isDirectory: true)
            if fileManager.fileExists(atPath: containers.path) {
                return containers
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return nil
    }

    #if DEBUG
    static func writeProbe(role: String) {
        var lines = [
            "role \(role)",
            "home \(NSHomeDirectory())"
        ]
        for id in [watchAppID, complicationID] {
            if let url = dataContainer(identifier: id) {
                lines.append("container \(id) \(url.path)")
            } else {
                lines.append("container \(id) nil")
            }
        }
        for url in fileURLs() {
            let name = (try? Data(contentsOf: url)).flatMap(decode)?.locationName ?? "missing"
            lines.append("file \(url.path) \(name)")
        }
        if let loaded = load() {
            lines.append("loaded \(loaded.locationName)")
        } else {
            lines.append("loaded nil")
        }
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let report = docs.appendingPathComponent("share-probe.txt", isDirectory: false)
        try? lines.joined(separator: "\n").data(using: .utf8)?.write(to: report, options: .atomic)
    }
    #endif

    private static func decode(_ data: Data) -> WatchPlace? {
        try? JSONDecoder().decode(WatchPlace.self, from: data)
    }
}
