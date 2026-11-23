import Foundation
import JavaScriptCore

@MainActor
final class ChessComTracker {
    private let context: JSContext
    private let readFrame: JSValue

    init(player: String) throws {
        guard let context = JSContext() else { throw TrackerError.failed("JavaScript недоступен.") }
        context.evaluateScript("var exports = {};")
        let resources = ["chess-rules", "ScreenGrid", "chesscom-profile", "chesscom-vision",
                         "MoveGlyphs", "MoveStrip", "CoachVision"]
        for resource in resources {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "js") else {
                throw TrackerError.failed("Отсутствует профиль доски.")
            }
            context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        }
        guard let factory = context.evaluateScript("(player) => coachVision.native(exports.Chess, chessComProfile, player)"),
              let reader = factory.call(withArguments: [player]), !reader.isUndefined,
              context.exception == nil else { throw TrackerError.failed("Не удалось открыть профиль доски.") }
        self.context = context
        readFrame = reader
    }

    func observe(_ frame: Frame) -> ChessTracker.Result? {
        guard let value = readFrame.call(withArguments: [frame.pixels.base64EncodedString(), frame.width, frame.height]),
              !value.isUndefined, let status = value.forProperty("status")?.toString() else { return nil }
        let line = value.forProperty("moveLine")
        let side = value.forProperty("turn")
        return ChessTracker.Result(status: status, ply: Int(value.forProperty("ply")?.toInt32() ?? 0),
                                   moveLine: line.flatMap { $0.isNull || $0.isUndefined ? nil : $0.toString() },
                                   turn: side.flatMap { $0.isNull || $0.isUndefined ? nil : $0.toString() },
                                   pieces: Int(value.forProperty("pieces")?.toInt32() ?? 32))
    }
}
