import Foundation

public struct MemorySnapshot: Codable, Sendable {
    public var id: UUID
    public var text: String
    public var kind: String
    public var hero: String
    public var role: String
    public var patch: String
    public var source: String
    public var enabled: Bool
    public init(id: UUID = UUID(), text: String, kind: String = "Предпочтение", hero: String = "", role: String = "", patch: String = "", source: String = "", enabled: Bool = true) {
        self.id = id; self.text = text; self.kind = kind; self.hero = hero; self.role = role
        self.patch = patch; self.source = source; self.enabled = enabled
    }
}
public enum MemoryRetrieval {
    private static func tokens(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
    }
    public static func retrieve(_ query: String, from entries: [MemorySnapshot], limit: Int = 6) -> [MemorySnapshot] {
        let wanted = tokens(query)
        return entries.filter(\.enabled).map { entry in
            let score = wanted.intersection(tokens("\(entry.text) \(entry.hero) \(entry.role)")).count
            return (entry, score)
        }.filter { $0.1 > 0 }.sorted {
            if $0.1 == $1.1 { return $0.0.id.uuidString < $1.0.id.uuidString }
            return $0.1 > $1.1
        }.prefix(max(0, limit)).map(\.0)
    }
    public static func context(_ entries: [MemorySnapshot]) -> String {
        entries.map { "[\($0.kind); герой=\($0.hero); роль=\($0.role); патч=\($0.patch); источник=\($0.source)] \($0.text.prefix(800))" }.joined(separator: "\n")
    }
}
