import Foundation
import JavaScriptCore

@MainActor
final class ChessComTracker {
    private let context: JSContext
    private let readFrame: JSValue

    init(player: String) throws {
        guard let context = JSContext() else { throw TrackerError.failed("JavaScript недоступен.") }
        context.evaluateScript("var exports = {};")
        for resource in ["chess-rules", "chesscom-profile", "chesscom-vision"] {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "js") else {
                throw TrackerError.failed("Отсутствует профиль доски.")
            }
            context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        }
        context.evaluateScript("""
        function makeNativeTracker(player) {
          const tracker = chessComVision.track(exports.Chess);
          let top, candidate, accepted;
          const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
          const table = new Uint8Array(128);
          for (let i=0;i<alphabet.length;i++) table[alphabet.charCodeAt(i)]=i;
          return function(encoded,width,height) {
            const data = new Uint8Array(width*height*4);
            for (let i=0,j=0;i<encoded.length;i+=4,j+=3) {
              const a=table[encoded.charCodeAt(i)], b=table[encoded.charCodeAt(i+1)];
              const c=table[encoded.charCodeAt(i+2)], d=table[encoded.charCodeAt(i+3)];
              data[j]=(a<<2)|(b>>4); data[j+1]=(b<<4)|(c>>2); data[j+2]=(c<<6)|d;
            }
            const hit=chessComVision.readFrame({width,height,data},chessComProfile,top);
            if(!hit){candidate=undefined;return {status:'uncertain'};}
            top=hit.top;
            const key=hit.labels.join('');
            if(key!==accepted&&key!==candidate){candidate=key;return {status:'checking'};}
            if(!tracker.update(hit.labels))return {status:'uncertain'};
            accepted=key;
            const game=tracker.game;
            const history=game.history({verbose:true});
            return {status:game.isGameOver()?'ended':'tracking',ply:history.length,
                    turn:game.turn(),
                    moveLine:game.turn()===player?history.map(move=>move.lan).join(' '):null};
          };
        }
        """)
        guard let factory = context.objectForKeyedSubscript("makeNativeTracker"),
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
                                   turn: side.flatMap { $0.isNull || $0.isUndefined ? nil : $0.toString() })
    }
}
