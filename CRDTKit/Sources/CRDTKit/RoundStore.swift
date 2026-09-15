import Foundation

// MARK: - Protocol

public protocol RoundStore {
    func save(_ state: RoundState) throws
    func load(id: UUID) throws -> RoundState?
    func listRounds() throws -> [UUID]
    func delete(id: UUID) throws
}

// MARK: - FileRoundStore

public final class FileRoundStore: RoundStore {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    public func save(_ state: RoundState) throws {
        let data = try encoder.encode(state)
        let final = fileURL(for: state.id)
        let tmp = final.appendingPathExtension("tmp")

        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(final, withItemAt: tmp)
    }

    public func load(id: UUID) throws -> RoundState? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(RoundState.self, from: data)
    }

    public func listRounds() throws -> [UUID] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        return contents.compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            return UUID(uuidString: url.deletingPathExtension().lastPathComponent)
        }
    }

    public func delete(id: UUID) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
