import Combine
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit
import UIKit
import UserNotifications

@MainActor
final class Coach: ObservableObject {
    @Published private(set) var message = "Начните захват перед первым ходом."
    @Published private(set) var snapshot: Frame?
    @Published private(set) var capturing = false
    @Published private(set) var tracking = false
    @Published private(set) var choosing = false
    @Published private(set) var lastHint: String?
    @Published var whiteAtBottom = true
    @Published var player = "w"
    @Published var useChessComProfile = true
    @Published var pace: HintPace = .medium
    private var profile: ChessComTracker?
    private var budget = HintBudget()
    private var turnObservedAt = ProcessInfo.processInfo.systemUptime
    private var observedPly = -1
    private var uncertainSince: TimeInterval?
    private let notificationID = "vesper.move"

    private let output = CaptureOutput()
    private let frames = DispatchQueue(label: "vesper.capture", qos: .userInitiated)
    private let notices = UNUserNotificationCenter.current()
    private var stream: SCStream?
    private var pickerInstalled = false
    private var tracker: ChessTracker?
    private var board: CGRect?
    private var latestFrame = 0
    private var confirmation: Task<Void, Never>?
    private var queuedLine: String?
    private var displayedLine: String?
    private var calculation: Task<Void, Never>?
    private var calibrationFrame: Frame?
    private var snapshotTask: Task<Void, Never>?

    init() { output.model = self }

    func chooseScreen() {
        guard !choosing, stream == nil else { return }
        choosing = true
        NativeEngine.prepare()
        let picker = SCContentSharingPicker.shared
        if !pickerInstalled {
            picker.add(output)
            pickerInstalled = true
        }
        picker.isActive = true
        picker.present()
    }

    func pickerCancelled() {
        choosing = false
        message = "Выбор экрана отменён."
    }

    func pickerFailed(_ error: Error) {
        choosing = false
        message = error.localizedDescription
    }

    func start(filter: SCContentFilter) async {
        guard choosing, stream == nil else { return }
        choosing = false
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = false
        let source = SCStream(filter: filter, configuration: configuration, delegate: output)
        stream = source
        do {
            try source.addStreamOutput(output, type: .screen, sampleHandlerQueue: frames)
            try await source.startCapture()
            guard stream === source else { return }
            budget = HintBudget()
            observedPly = -1
            if useChessComProfile {
                profile = try ChessComTracker(player: player)
            }
            capturing = true
            snapshot = nil
            message = profile == nil
                ? "Переключитесь на игру с начальной позицией, подождите пару секунд и вернитесь."
                : "Откройте текущую позицию в Chess.com. Доска будет найдена автоматически."
            let allowed = (try? await notices.requestAuthorization(options: [.alert])) == true
            guard stream === source, !allowed else { return }
            message += " Без разрешения подсказки будут видны только здесь."
        } catch {
            guard stream === source else { return }
            endSession()
            stream = nil
            try? await source.stopCapture()
            message = error.localizedDescription
        }
    }

    func captureStopped(_ source: SCStream, error: Error) {
        guard source === stream else { return }
        endSession()
        stream = nil
        message = "Захват остановлен. " + error.localizedDescription
    }

    func stop() async {
        guard let source = stream else { return }
        endSession()
        stream = nil
        try? await source.stopCapture()
        if stream == nil { message = "Захват остановлен." }
    }

    func retake() {
        guard capturing else { return }
        tracker = nil
        profile = nil
        tracking = false
        snapshot = nil
        snapshotSize = nil
        board = nil
        observedPly = -1
        uncertainSince = nil
        budget = HintBudget()
        confirmation?.cancel()
        clearHint()
        message = "Переключитесь на игру с начальной позицией, подождите пару секунд и вернитесь."
    }

    func setCalibration(_ region: CGRect) {
        guard let snapshot, let marks = snapshot.signatures(in: region) else {
            message = "Обведите всю контрастную доску 8×8, от края до края."
            return
        }
        do {
            tracker = try ChessTracker(initial: marks, whiteAtBottom: whiteAtBottom, player: player)
            board = region
            snapshotSize = (snapshot.width, snapshot.height)
            self.snapshot = nil
            tracking = true
            clearHint()
            message = "Доска настроена. Откройте игру и дождитесь подтверждения позиции."
        } catch {
            message = error.localizedDescription
        }
    }

    func receive(_ frame: Frame, source: ObjectIdentifier) {
        guard let stream, source == ObjectIdentifier(stream), capturing else { return }
        guard UIApplication.shared.applicationState == .background else { return }
        if let profile {
            latestFrame += 1
            let revision = latestFrame
            confirmation?.cancel()
            if handle(profile.observe(frame)) {
                confirmation = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(85))
                    guard !Task.isCancelled, let self, self.latestFrame == revision,
                          UIApplication.shared.applicationState == .background else { return }
                    _ = self.handle(profile.observe(frame))
                }
            }
            return
        }
        guard tracker != nil else {
            considerCalibrationFrame(frame)
            return
        }
        latestFrame += 1
        let revision = latestFrame
        confirmation?.cancel()
        guard let snapshotSize, frame.width == snapshotSize.width, frame.height == snapshotSize.height,
              let board, let marks = frame.signatures(in: board) else {
            _ = handle(nil)
            return
        }
        if confirm(marks) {
            confirmation = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(85))
                guard !Task.isCancelled, let self, self.latestFrame == revision,
                      UIApplication.shared.applicationState == .background else { return }
                _ = self.confirm(marks)
            }
        }
    }

    private var snapshotSize: (width: Int, height: Int)?

    private func considerCalibrationFrame(_ frame: Frame) {
        guard snapshot == nil else { return }
        calibrationFrame = frame
        guard snapshotTask == nil else { return }
        snapshotTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled, let self else { return }
            self.snapshotTask = nil
            guard self.capturing, UIApplication.shared.applicationState == .background else { return }
            self.snapshot = self.calibrationFrame
            self.calibrationFrame = nil
        }
    }

    func becameActive() {
        snapshotTask?.cancel()
        snapshotTask = nil
        calibrationFrame = nil
        confirmation?.cancel()
        if !tracking, snapshot != nil {
            message = "Обведите границы доски, укажите ориентацию и цвет, затем нажмите «Отслеживать»."
        }
    }

    private func confirm(_ marks: [[Int]]) -> Bool {
        return handle(tracker?.observe(marks))
    }

    private func handle(_ observation: ChessTracker.Result?) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard let result = observation else { positionUncertain(at: now); return false }
        switch result.status {
        case "checking":
            return true
        case "tracking":
            uncertainSince = nil
            tracking = true
            if observedPly != result.ply {
                observedPly = result.ply
                turnObservedAt = now
            }
            let progress = "Распознано полуходов — \(result.ply)."
            if message != progress { message = progress }
            if let line = result.moveLine { queueHint(line, position: result) }
            else { clearHint(removeNotification: false) }
        case "ended":
            clearHint()
            message = "Партия завершена."
        case "reviewing":
            clearHint()
            message = "Вы просматриваете историю. Вернитесь к последнему ходу."
        default:
            positionUncertain(at: now)
        }
        return false
    }

    private func positionUncertain(at now: TimeInterval) {
        if uncertainSince == nil { uncertainSince = now }
        if let uncertainSince, now - uncertainSince >= 0.32 {
            clearHint()
            message = "Жду, когда доска снова станет видна."
        }
    }

    private func queueHint(_ line: String, position: ChessTracker.Result) {
        guard line != queuedLine, line != displayedLine else { return }
        let search = pace.searchTime(ply: position.ply, pieces: position.pieces,
                                     spent: budget.spent, overhead: budget.overhead)
        queuedLine = line
        calculation?.cancel()
        let revision = NativeEngine.replaceSearch()
        let started = ProcessInfo.processInfo.systemUptime
        calculation = Task { [weak self] in
            let move = await NativeEngine.suggest(history: line, milliseconds: search, revision: revision)
            guard !Task.isCancelled, let self, self.queuedLine == line else { return }
            self.queuedLine = nil
            guard let move else { self.message = "Stockfish не вернул ход."; return }
            self.displayedLine = line
            let now = ProcessInfo.processInfo.systemUptime
            self.budget.record(turn: now - self.turnObservedAt, search: now - started)
            let body = "\(move.prefix(2)) → \(move.dropFirst(2).prefix(2))"
            let promotion = ["q": "ферзь", "r": "ладья", "b": "слон", "n": "конь"]
            let hint = body + (move.count == 5 ? " · " + (promotion[String(move.suffix(1))] ?? "") : "")
            self.lastHint = hint
            let content = UNMutableNotificationContent()
            content.title = "Ход"
            content.body = hint
            content.threadIdentifier = self.notificationID
            do {
                try await self.notices.add(UNNotificationRequest(identifier: self.notificationID, content: content,
                                                                  trigger: nil))
            } catch {
                if self.displayedLine == line { self.message = "Ход рассчитан. Баннер недоступен." }
            }
        }
    }

    private func clearHint(removeNotification: Bool = true) {
        if queuedLine != nil {
            calculation?.cancel()
            _ = NativeEngine.replaceSearch()
        }
        queuedLine = nil
        lastHint = nil
        displayedLine = nil
        if removeNotification {
            notices.removePendingNotificationRequests(withIdentifiers: [notificationID])
            notices.removeDeliveredNotifications(withIdentifiers: [notificationID])
        }
    }

    private func endSession() {
        capturing = false
        tracking = false
        tracker = nil
        profile = nil
        uncertainSince = nil
        snapshot = nil
        snapshotSize = nil
        board = nil
        snapshotTask?.cancel()
        snapshotTask = nil
        calibrationFrame = nil
        displayedLine = nil
        confirmation?.cancel()
        clearHint()
    }
}
