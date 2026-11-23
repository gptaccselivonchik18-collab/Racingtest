import Foundation
import JavaScriptCore

@MainActor
final class ChessTracker {
    struct Result {
        let status: String
        let ply: Int
        let moveLine: String?
        var turn: String? = nil
        var pieces: Int = 32
    }

    private let context: JSContext
    private let tracker: JSValue

    init(initial: [[Int]], whiteAtBottom: Bool, player: String) throws {
        guard let context = JSContext(),
              let chess = Bundle.main.url(forResource: "chess-rules", withExtension: "js"),
              let tracker = Bundle.main.url(forResource: "BoardTracker", withExtension: "js") else {
            throw TrackerError.failed("Файлы правил шахмат отсутствуют.")
        }
        context.evaluateScript("var exports = {};")
        context.evaluateScript(try String(contentsOf: chess, encoding: .utf8))
        context.evaluateScript(try String(contentsOf: tracker, encoding: .utf8))
        guard let factory = context.objectForKeyedSubscript("makeBoardTracker"),
              let rules = context.evaluateScript("exports.Chess"),
              let value = factory.call(withArguments: [rules, initial, whiteAtBottom, player]),
              !value.isUndefined, context.exception == nil else {
            throw TrackerError.failed(context.exception?.toString() ?? "Не удалось подготовить доску.")
        }
        self.context = context
        self.tracker = value
    }

    func observe(_ signatures: [[Int]]) -> Result? {
        guard let value = tracker.invokeMethod("observe", withArguments: [signatures]),
              !value.isUndefined, let status = value.forProperty("status")?.toString() else { return nil }
        let line = value.forProperty("moveLine")
        let side = value.forProperty("turn")
        return Result(status: status, ply: Int(value.forProperty("ply")?.toInt32() ?? 0),
                      moveLine: line.flatMap { $0.isNull || $0.isUndefined ? nil : $0.toString() },
                      turn: side.flatMap { $0.isNull || $0.isUndefined ? nil : $0.toString() },
                      pieces: Int(value.forProperty("pieces")?.toInt32() ?? 32))
    }
}

enum TrackerError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self { case let .failed(message): return message }
    }
}
