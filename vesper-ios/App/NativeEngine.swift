import Foundation

enum NativeEngine {
    private static let queue = DispatchQueue(label: "vesper.stockfish", qos: .userInitiated)

    static func replaceSearch() -> UInt64 { vesper_replace_search() }

    static func prepare() {
        let revision = replaceSearch()
        Task { _ = await suggest(history: "", milliseconds: 1, revision: revision) }
    }

    static func suggest(history: String, milliseconds: Int32, revision: UInt64) async -> String? {
        guard let path = Bundle.main.path(forResource: "nn-1a298aa575a0", ofType: "nnue") else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                var output = [CChar](repeating: 0, count: 6)
                let length = output.count
                let status = path.withCString { network in
                    history.withCString { moves in
                        vesper_best_move_for(revision, network, moves, milliseconds, &output, length)
                    }
                }
                continuation.resume(returning: status == 1 ? String(cString: output) : nil)
            }
        }
    }
}
