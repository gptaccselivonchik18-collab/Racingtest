import Foundation

public enum DataValidationError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
public struct KnowledgePack: Codable, Sendable {
    public var schemaVersion: Int
    public var patch: String
    public var published: Date
    public var source: String
    public var license: String
    public var entries: [String]
    public func validate() throws {
        guard schemaVersion == 1, !patch.trimmingCharacters(in: .whitespaces).isEmpty, patch.count <= 100,
              let url = URL(string: source), url.scheme == "https", url.host != nil,
              !license.isEmpty, license.count <= 2000, !entries.isEmpty, entries.count <= 500,
              entries.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 4000 }) else {
            throw DataValidationError.invalid("Некорректный пакет: нужны версия схемы 1, патч, HTTPS-источник, лицензия и 1–500 записей до 4000 символов")
        }
    }
    public static func decode(_ data: Data) throws -> KnowledgePack {
        guard data.count <= 2_000_000 else { throw DataValidationError.invalid("Пакет знаний превышает 2 МБ") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let pack = try decoder.decode(Self.self, from: data); try pack.validate(); return pack
    }
}
public struct MemoryBackup: Codable {
    public var schemaVersion: Int
    public var entries: [MemorySnapshot]
    public init(entries: [MemorySnapshot]) { schemaVersion = 1; self.entries = entries }
    public static func decode(_ data: Data) throws -> MemoryBackup {
        guard data.count <= 20_000_000 else { throw DataValidationError.invalid("Резервная копия превышает 20 МБ") }
        let backup = try JSONDecoder().decode(Self.self, from: data)
        guard backup.schemaVersion == 1, backup.entries.count <= 5000,
              Set(backup.entries.map(\.id)).count == backup.entries.count,
              backup.entries.allSatisfy({ !$0.text.isEmpty && $0.text.count <= 8000 && $0.source.count <= 2000 && ["Факт с источником", "Предпочтение", "Гипотеза", "Исправление"].contains($0.kind) }) else {
            throw DataValidationError.invalid("Неподдерживаемая версия, повторные ID или некорректные записи памяти")
        }
        return backup
    }
}
