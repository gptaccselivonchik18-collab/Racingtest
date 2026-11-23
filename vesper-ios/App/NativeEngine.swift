import Foundation

enum NativeEngine {
    private static let queue = DispatchQueue(label: "vesper.stockfish", qos: .userInitiated)

    static func suggest(history: String, milliseconds: Int32) async -> String? {
        guard let path = Bundle.main.path(forResource: "nn-1a298aa575a0", ofType: "nnue") else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                var output = [CChar](repeating: 0, count: 6)
                let length = output.count
                let status = path.withCString { network in
                    history.withCString { moves in
                        vesper_best_move(network, moves, milliseconds, &output, length)
                    }
                }
                continuation.resume(returning: status == 1 ? String(cString: output) : nil)
            }
        }
    }
}
