import Foundation

public struct RecognizedIcon: Codable, Sendable {
    public let slot: String
    public let code: String
    public let score: Double
    public let observedAt: Double
    public init(slot: String, code: String, score: Double, observedAt: Double) { self.slot = slot; self.code = code; self.score = score; self.observedAt = observedAt }
}
public struct StrategicState: Codable, Sendable {
    public var ownHealth: Double?
    public var icons: [RecognizedIcon]
    public var unknowns = ["positions", "cooldowns", "gold", "patch_statistics", "team_intentions"]
    public init(ownHealth: Double?, icons: [RecognizedIcon]) { self.ownHealth = ownHealth; self.icons = icons }
    public func englishJSON() throws -> String {
        // Arbitrary OCR, chat, memory and user labels NEVER enter the Apple English-only route.
        guard unknowns == ["positions", "cooldowns", "gold", "patch_statistics", "team_intentions"], icons.count <= 12, icons.allSatisfy({ $0.code.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 } && ["ally", "enemy", "unknown"].contains($0.slot) && $0.score.isFinite && $0.observedAt.isFinite }),
              ownHealth.map({ $0.isFinite && $0 >= 0 && $0 <= 1 }) ?? true else { throw NeuralError.invalidData }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

public enum GameAction: String, Codable, CaseIterable, Sendable { case gatherInformation, recover, farm, rotate, contestObjective, retreat, pressureTower }
public enum DecisionReason: String, Codable, Sendable { case insufficientEvidence, healthLimited, resourceOpportunity, numericalAdvantage, enemyMissing, objectiveWindow }
public struct ActionOption: Codable, Sendable {
    public let action: GameAction
    public let reason: DecisionReason
    public let utility: Int
    public let risk: Int
    public init(action: GameAction, reason: DecisionReason, utility: Int, risk: Int) { self.action = action; self.reason = reason; self.utility = utility; self.risk = risk }
}
public struct StrategicPlan: Codable, Sendable {
    public let selected: GameAction
    public let alternatives: [ActionOption]
    public let confidence: Int
    public var valid: Bool { (0...100).contains(confidence) && (2...5).contains(alternatives.count) && Set(alternatives.map(\.action)).count == alternatives.count && alternatives.contains { $0.action == selected } && alternatives.allSatisfy { (0...100).contains($0.utility) && (0...100).contains($0.risk) } }
    public init(selected: GameAction, alternatives: [ActionOption], confidence: Int) { self.selected = selected; self.alternatives = alternatives; self.confidence = confidence }
    public func russian() -> String {
        func action(_ value: GameAction) -> String {
            switch value { case .gatherInformation: return "Уточните обстановку"; case .recover: return "Найдите безопасное восстановление"; case .farm: return "Рассмотрите фарм"; case .rotate: return "Рассмотрите ротацию"; case .contestObjective: return "Рассмотрите борьбу за объект"; case .retreat: return "Рассмотрите отход"; case .pressureTower: return "Рассмотрите давление на башню" }
        }
        func reason(_ value: DecisionReason) -> String {
            switch value { case .insufficientEvidence: return "наблюдений недостаточно"; case .healthLimited: return "запас здоровья ограничен"; case .resourceOpportunity: return "возможность получить ресурсы"; case .numericalAdvantage: return "предполагаемое численное преимущество"; case .enemyMissing: return "позиции врагов неизвестны"; case .objectiveWindow: return "предполагаемое окно для объекта" }
        }
        let chosen = alternatives.first { $0.action == selected }
        let rows = alternatives.map { "\(action($0.action)): \(reason($0.reason)); полезность \($0.utility), риск \($0.risk) из 100" }.joined(separator: "\n")
        return "\(action(selected)) — \(chosen.map { reason($0.reason) } ?? "нет основания").\nАльтернативы модели:\n\(rows)\nУверенность модели: \(confidence)/100. Оценки не являются измеренными вероятностями. Невидимые события и характеристики патча неизвестны."
    }
}
