import CoreMedia
import Foundation
import ScreenCaptureKit

final class CaptureOutput: NSObject, SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate {
    weak var model: Coach?
    private let converter = FrameConverter()
    // Accessed only from the serial sample queue.
    private var lastFrameAt: TimeInterval = 0
    private let handoff = NSLock()
    private var pending: (Frame, ObjectIdentifier)?
    private var deliveryScheduled = false

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in self.model?.pickerCancelled() }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter,
                              for stream: SCStream?) {
        Task { @MainActor in await self.model?.start(filter: filter) }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in self.model?.pickerFailed(error) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.model?.captureStopped(stream, error: error) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        let now = ProcessInfo.processInfo.systemUptime
        guard outputType == .screen, now - lastFrameAt >= 0.062,
              let pixelBuffer = CMSampleBufferGetImageBuffer(buffer),
              let frame = converter.convert(pixelBuffer) else { return }
        lastFrameAt = now
        handoff.lock()
        pending = (frame, ObjectIdentifier(stream))
        let schedule = !deliveryScheduled
        deliveryScheduled = true
        handoff.unlock()
        if schedule { Task { @MainActor in self.deliverLatest() } }
    }

    @MainActor private func deliverLatest() {
        handoff.lock()
        let frame = pending
        pending = nil
        deliveryScheduled = false
        handoff.unlock()
        if let (image, source) = frame { model?.receive(image, source: source) }
    }
}
