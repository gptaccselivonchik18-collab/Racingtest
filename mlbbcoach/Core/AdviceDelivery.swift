import Foundation

public enum AdviceMode: String, CaseIterable, Codable, Sendable {
    case voiceAndText, voiceOnly, textOnly
    public var usesVoice: Bool { self != .textOnly }
    public var usesText: Bool { self != .voiceOnly }
}

public struct AdviceEpisode: Codable, Identifiable, Sendable {
    public let id: UUID
    public let created: Date
    public let sessionID: UUID
    public let key: String
    public let text: String
    public let priority: Int
    public let observedHP: Double?
    public let evidence: String
    public let uncertainty: String
    public var rating: Int = 0
    public var correction: String = ""
    public init(id: UUID, sessionID: UUID, key: String, text: String, priority: Int, observedHP: Double?) {
        self.id = id; self.created = .now; self.sessionID = sessionID; self.key = key
        self.text = text; self.priority = priority; self.observedHP = observedHP
        evidence = "Два согласованных измерения в области собственного HP, указанной пользователем."
        uncertainty = "Герои, противники, миникарта, действия игрока и результат решения неизвестны."
    }
}

public struct AdviceRepeatGate: Sendable {
    private var last: [String: Double] = [:]
    private var lastAny: Double?
    public init() {}
    public mutating func admit(key: String, priority: Int, now: Double, repeatSeconds: Double, interval: Double) -> Bool {
        guard now.isFinite, now >= 0 else { return false }
        if let previous = last[key], now - previous < max(5, repeatSeconds) { return false }
        if priority != 1, let previous = lastAny, now - previous < max(5, interval) { return false }
        last[key] = now; lastAny = now
        if last.count > 100 { last = last.filter { now - $0.value < max(5, repeatSeconds) } }
        return true
    }
}
