import Foundation

public enum SceneStoreError: Error, Equatable {
    case notFound(String)
}

/// Reads and writes Scenes as `<name>.json` files in a directory.
public protocol SceneStore {
    func list() throws -> [String]
    func load(_ name: String) throws -> Scene
    func save(_ scene: Scene) throws
}

public struct FileSceneStore: SceneStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func list() throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        return urls
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    public func load(_ name: String) throws -> Scene {
        let url = fileURL(for: name)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw SceneStoreError.notFound(name)
        }
        return try Scene.load(fromJSON: data)
    }

    public func save(_ scene: Scene) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        try scene.encodedJSON().write(to: fileURL(for: scene.name))
    }

    private func fileURL(for name: String) -> URL {
        directory.appendingPathComponent(name).appendingPathExtension("json")
    }
}
