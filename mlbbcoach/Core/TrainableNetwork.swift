import Foundation

public struct LabeledVector: Codable, Sendable {
    public let id: UUID
    public let group: String
    public let features: [Double]
    public let label: Int
    public init(group: String, features: [Double], label: Int) { id = UUID(); self.group = group; self.features = features; self.label = label }
}
public struct NetworkMetrics: Codable, Sendable {
    public let count: Int
    public let accuracy: Double
    public let loss: Double
}
// Fully connected neural network: tanh hidden layer, softmax output, cross-entropy SGD/backpropagation.
// No rules or nearest-neighbour lookup substitute for its trainable parameters.
public struct TrainableNetwork: Codable, Sendable {
    public let inputs: Int
    public let hidden: Int
    public let outputs: Int
    public var w1: [Double]
    public var b1: [Double]
    public var w2: [Double]
    public var b2: [Double]
    public init(inputs: Int, hidden: Int = 24, outputs: Int, seed: UInt64 = 42) {
        self.inputs = inputs; self.hidden = hidden; self.outputs = outputs
        var state = seed
        func random(_ scale: Double) -> Double { state = state &* 6364136223846793005 &+ 1; return (Double(state >> 11) / 9007199254740992 * 2 - 1) * scale }
        w1 = (0..<inputs * hidden).map { _ in random(sqrt(6 / Double(inputs + hidden))) }; b1 = Array(repeating: 0, count: hidden)
        w2 = (0..<hidden * outputs).map { _ in random(sqrt(6 / Double(hidden + outputs))) }; b2 = Array(repeating: 0, count: outputs)
    }
    public var valid: Bool {
        inputs > 0 && inputs <= 1024 && hidden > 0 && hidden <= 64 && outputs >= 2 && outputs <= 64 &&
        w1.count == inputs * hidden && w2.count == hidden * outputs && b1.count == hidden && b2.count == outputs &&
        (w1 + w2 + b1 + b2).allSatisfy { $0.isFinite }
    }
    private func forward(_ x: [Double]) -> (h: [Double], p: [Double])? {
        guard valid, x.count == inputs, x.allSatisfy({ $0.isFinite && abs($0) <= 10 }) else { return nil }
        var h = b1, z = b2
        for j in 0..<hidden { for i in 0..<inputs { h[j] += w1[j * inputs + i] * x[i] }; h[j] = tanh(h[j]) }
        for k in 0..<outputs { for j in 0..<hidden { z[k] += w2[k * hidden + j] * h[j] } }
        guard z.allSatisfy(\.isFinite) else { return nil }
        let peak = z.max() ?? 0; let e = z.map { exp($0 - peak) }; let sum = e.reduce(0,+)
        return (h, e.map { $0 / sum })
    }
    public func probabilities(_ x: [Double]) -> [Double]? { forward(x)?.p }
    public func metrics(_ samples: [LabeledVector]) -> NetworkMetrics? {
        guard !samples.isEmpty else { return nil }
        var correct = 0, loss = 0.0
        for sample in samples {
            guard (0..<outputs).contains(sample.label), let p = probabilities(sample.features) else { return nil }
            if p.indices.max(by: { p[$0] < p[$1] }) == sample.label { correct += 1 }
            loss -= log(max(1e-12, p[sample.label]))
        }
        return NetworkMetrics(count: samples.count, accuracy: Double(correct)/Double(samples.count), loss: loss/Double(samples.count))
    }
    public mutating func train(_ samples: [LabeledVector], epochs: Int = 35, rate: Double = 0.015) throws {
        guard valid, !samples.isEmpty, samples.count <= 500, epochs > 0, epochs <= 100, rate.isFinite, rate > 0, rate <= 0.2 else { throw NeuralError.invalidData }
        for _ in 0..<epochs {
            try Task.checkCancellation()
            for sample in samples {
                guard (0..<outputs).contains(sample.label), let (h, p) = forward(sample.features) else { throw NeuralError.invalidData }
                var dz = p; dz[sample.label] -= 1
                var dh = Array(repeating: 0.0, count: hidden)
                for j in 0..<hidden { for k in 0..<outputs { dh[j] += w2[k * hidden + j] * dz[k] }; dh[j] *= 1 - h[j] * h[j] }
                for k in 0..<outputs { for j in 0..<hidden { w2[k * hidden + j] -= rate * dz[k] * h[j] }; b2[k] -= rate * dz[k] }
                for j in 0..<hidden { for i in 0..<inputs { w1[j * inputs + i] -= rate * dh[j] * sample.features[i] }; b1[j] -= rate * dh[j] }
            }
        }
        guard valid else { throw NeuralError.invalidData }
    }
    public static func validateSplit(train: [LabeledVector], test: [LabeledVector], classes: Int) throws {
        guard !train.isEmpty, !test.isEmpty, Set(train.map(\.group)).isDisjoint(with: Set(test.map(\.group))),
              Set(train.map(\.id)).isDisjoint(with: Set(test.map(\.id))), classes >= 2,
              (0..<classes).allSatisfy({ label in train.filter { $0.label == label }.count >= 3 && test.filter { $0.label == label }.count >= 2 }) else { throw NeuralError.invalidSplit }
    }
    public static func shouldPromote(before: NetworkMetrics, after: NetworkMetrics) -> Bool {
        before.count == after.count && after.count > 0 && after.accuracy >= 0.7 && after.accuracy >= before.accuracy && after.loss < before.loss
    }
}
public enum NeuralError: LocalizedError {
    case invalidData, invalidSplit
    public var errorDescription: String? {
        switch self {
        case .invalidData: return "Некорректные параметры или данные нейросети"
        case .invalidSplit: return "Нужны минимум 2 класса, по 3 обучающих и 2 проверочных примера каждого. Скриншоты одной группы не могут попадать в обе выборки."
        }
    }
}

public struct IconLabel: Codable, Sendable, Hashable {
    public let code: String
    public let russian: String
    public init(code: String, russian: String) { self.code = code; self.russian = russian }
    public var valid: Bool { !code.isEmpty && code.count <= 40 && code.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 } && !russian.isEmpty }
}
public struct IconNetworkVersion: Codable, Sendable {
    public let id: UUID
    public let labels: [IconLabel]
    public let network: TrainableNetwork
    public let before: NetworkMetrics
    public let after: NetworkMetrics
    public let parametersChanged: Bool
    public let created: Date
    public init(labels: [IconLabel], network: TrainableNetwork, before: NetworkMetrics, after: NetworkMetrics, parametersChanged: Bool) {
        id = UUID(); self.labels = labels; self.network = network; self.before = before; self.after = after; self.parametersChanged = parametersChanged; created = .now
    }
    public var valid: Bool { network.valid && network.inputs == 768 && labels.count == network.outputs && labels.allSatisfy(\.valid) && Set(labels.map(\.code)).count == labels.count }
}
