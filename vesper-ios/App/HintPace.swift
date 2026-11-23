import Foundation

enum HintPace: Int, CaseIterable {
    case flash, medium, hard

    var title: String {
        switch self {
        case .flash: return "Молниеносно"
        case .medium: return "Средне"
        case .hard: return "Сложный"
        }
    }

    func searchTime(ply: Int, pieces: Int, spent: TimeInterval, overhead: TimeInterval) -> Int32 {
        let index = rawValue
        if ply == 0 { return [150, 1250, 2500][index] }
        if ply == 1 { return [220, 2200, 8000][index] }
        let target: [Double] = [60_000, 180_000, 600_000]
        let floor = [80, 330, 850][index]
        let ceiling = [270, 2900, 9300][index]
        let turns = max(14, Int((48 - Double(ply / 2) * 0.5 - Double(32 - pieces) * 0.5).rounded()))
        let available = (target[index] * 0.86 - spent * 1000) / Double(turns) - overhead * 1000
        return Int32(min(ceiling, max(floor, Int(available.rounded()))))
    }
}

struct HintBudget {
    var spent: TimeInterval = 0
    private(set) var overhead: TimeInterval = 0.14

    mutating func record(turn: TimeInterval, search: TimeInterval) {
        spent += max(0, turn)
        overhead = overhead * 0.75 + max(0, turn - search) * 0.25
    }
}
