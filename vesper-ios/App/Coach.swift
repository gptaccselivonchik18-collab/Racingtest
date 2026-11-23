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
    private var leftAppAt: Date?
    private var calibrationFrame: Frame?
    private var snapshotTask: Task<Void, Never>?

    init() { output.model = self }

    func chooseScreen() {
        guard !choosing, stream == nil else { return }
        choosing = true
        let picker = SCContentSharingPicker.shared
        if !pickerInstalled {
            picker.add(output)
            pickerInstalled = true
        }
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleDisplay]
        configuration.allowsChangingSelectedContent = false
        picker.defaultConfiguration = configuration
        picker.maximumStreamCount = 1
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
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 8)
        configuration.queueDepth = 3
        configuration.capturesAudio = false
        let source = SCStream(filter: filter, configuration: configuration, delegate: output)
        stream = source
        do {
            try source.addStreamOutput(output, type: .screen, sampleHandlerQueue: frames)
            try await source.startCapture()
            guard stream === source else { return }
            capturing = true
            snapshot = nil
            message = "Переключитесь на игру с начальной позицией, подождите пару секунд и вернитесь."
            let allowed = (try? await notices.requestAuthorization(options: [.alert])) == true
            guard stream === source, !allowed else { return }
            message += " Без разрешения подсказки будут видны только здесь."
        } catch {
            guard stream === source else { return }
            endSession()
            stream = nil
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
        tracking = false
        snapshot = nil
        snapshotSize = nil
        board = nil
        displayedLine = nil
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
        let now = Date()
        if leftAppAt == nil { leftAppAt = now }
        guard tracker != nil else {
            considerCalibrationFrame(frame)
            return
        }
        guard let leftAppAt, now.timeIntervalSince(leftAppAt) >= 0.45 else { return }
        latestFrame += 1
        let revision = latestFrame
        confirmation?.cancel()
        guard let snapshotSize, frame.width == snapshotSize.width, frame.height == snapshotSize.height,
              let board, let marks = frame.signatures(in: board) else {
            clearHint()
            message = "Доска перекрыта или сдвинулась. Ожидаю исходную область."
            return
        }
        if confirm(marks) {
            confirmation = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
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
        leftAppAt = nil
        confirmation?.cancel()
        if !tracking, snapshot != nil {
            message = "Обведите границы доски, укажите ориентацию и цвет, затем нажмите «Отслеживать»."
        }
    }

    private func confirm(_ marks: [[Int]]) -> Bool {
        guard let result = tracker?.observe(marks) else { clearHint(); return false }
        switch result.status {
        case "checking":
            clearHint()
            return true
        case "tracking":
            message = "Распознано полуходов — \(result.ply)."
            if let line = result.moveLine { queueHint(line) } else { clearHint() }
        case "ended":
            clearHint()
            message = "Партия завершена."
        default:
            clearHint()
            message = "Позиция не подтверждена. Подсказка приостановлена."
        }
        return false
    }

    private func queueHint(_ line: String) {
        guard line != queuedLine, line != displayedLine else { return }
        queuedLine = line
        calculation?.cancel()
        calculation = Task { [weak self] in
            let move = await NativeEngine.suggest(history: line, milliseconds: 500)
            guard !Task.isCancelled, let self, self.queuedLine == line else { return }
            self.queuedLine = nil
            guard let move else { self.message = "Stockfish не вернул ход."; return }
            self.displayedLine = line
            let body = "\(move.prefix(2)) → \(move.dropFirst(2).prefix(2))"
            let promotion = ["q": "ферзь", "r": "ладья", "b": "слон", "n": "конь"]
            let hint = body + (move.count == 5 ? " · " + (promotion[String(move.suffix(1))] ?? "") : "")
            self.lastHint = hint
            let content = UNMutableNotificationContent()
            content.title = "Vesper Gambit · твой ход"
            content.body = hint
            do {
                try await self.notices.add(UNNotificationRequest(identifier: "vesper.move", content: content,
                                                                  trigger: nil))
            } catch {
                if self.displayedLine == line { self.message = "Ход рассчитан. Баннер недоступен." }
            }
        }
    }

    private func clearHint() {
        calculation?.cancel()
        queuedLine = nil
        if lastHint != nil {
            lastHint = nil
            notices.removeDeliveredNotifications(withIdentifiers: ["vesper.move"])
        }
    }

    private func endSession() {
        capturing = false
        tracking = false
        tracker = nil
        snapshot = nil
        snapshotSize = nil
        board = nil
        leftAppAt = nil
        snapshotTask?.cancel()
        snapshotTask = nil
        calibrationFrame = nil
        displayedLine = nil
        confirmation?.cancel()
        clearHint()
    }
}
