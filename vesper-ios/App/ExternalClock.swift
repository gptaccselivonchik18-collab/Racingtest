import Foundation

struct ExternalClock {
    private var values: [String: TimeInterval]
    private var side: String?
    private var started = ProcessInfo.processInfo.systemUptime

    init(minutes: Int) {
        values = ["w": Double(minutes * 60), "b": Double(minutes * 60)]
    }

    func seconds(for color: String) -> TimeInterval {
        max(0, values[color, default: 0] -
            (side == color ? ProcessInfo.processInfo.systemUptime - started : 0))
    }

    mutating func pause() {
        if let side { values[side] = seconds(for: side) }
        side = nil
    }

    mutating func resume(_ color: String) {
        guard color != side else { return }
        pause()
        side = color
        started = ProcessInfo.processInfo.systemUptime
    }

    var label: String {
        func format(_ color: String) -> String {
            let time = Int(ceil(seconds(for: color)))
            return String(format: "%d:%02d", time / 60, time % 60)
        }
        return "Оценка часов · белые \(format("w")) · чёрные \(format("b"))"
    }
}
