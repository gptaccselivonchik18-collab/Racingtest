import CoreMedia
import Foundation
import ScreenCaptureKit

final class CaptureOutput: NSObject, SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate {
    weak var model: Coach?
    private let converter = FrameConverter()

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
        guard outputType == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(buffer),
              let frame = converter.convert(pixelBuffer) else { return }
        let id = ObjectIdentifier(stream)
        Task { @MainActor in self.model?.receive(frame, source: id) }
    }
}
