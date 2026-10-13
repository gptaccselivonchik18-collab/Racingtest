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

public struct HUDRegion: Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= 1 && y + height <= 1
    }
}
public struct HealthObservation: Codable, Sendable {
    public let fraction: Double
    public let confidence: Double
    public let time: Double
    public init(fraction: Double, confidence: Double, time: Double) {
        self.fraction = fraction; self.confidence = confidence; self.time = time
    }
}
public enum HealthParser {
    public static func parse(_ text: String, confidence: Double, time: Double) -> HealthObservation? {
        guard confidence.isFinite, confidence >= 0.85, confidence <= 1, time.isFinite, time >= 0 else { return nil }
        let pieces = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 2 else { return nil }
        let values = pieces.map { $0.trimmingCharacters(in: .whitespaces) }
        guard values.allSatisfy({ !$0.isEmpty && $0.count <= 7 && $0.allSatisfy(\.isNumber) }),
              let current = Double(values[0]), let maximum = Double(values[1]), maximum > 0, current >= 0, current <= maximum else { return nil }
        return HealthObservation(fraction: current / maximum, confidence: confidence, time: time)
    }
}
public struct TacticalAdvice: Codable, Sendable {
    public let key: String
    public let priority: Int
    public let text: String
}
public enum TacticalDecisionEngine {
    public static func evaluate(health: HealthObservation?, at time: Double, maxAge: Double = 10) -> [TacticalAdvice] {
        guard let hp = health, hp.fraction.isFinite, hp.fraction > 0, hp.fraction <= 1,
              hp.confidence >= 0.85, hp.confidence <= 1, hp.time.isFinite, time.isFinite,
              time >= hp.time, time - hp.time <= maxAge else { return [] }
        if hp.fraction <= 0.15 {
            return [TacticalAdvice(key: "critical-hp", priority: 1, text: "По OCR HP около \(Int(hp.fraction * 100))%. Если область выбрана верно, избегайте размена и проверьте безопасный путь отхода.")]
        }
        if hp.fraction <= 0.30 {
            return [TacticalAdvice(key: "low-hp", priority: 2, text: "По OCR запас HP снижен. Оцените восстановление перед следующим боем; позиции противников неизвестны.")]
        }
        return []
    }
}
