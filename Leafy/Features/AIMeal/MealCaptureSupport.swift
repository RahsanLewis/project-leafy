import AVFAudio
import Observation
import SwiftUI
import UIKit

struct MealCameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.cameraCaptureMode = .photo
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: MealCameraPicker
        init(parent: MealCameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

extension UIImage {
    func leafyMealJPEG(maxDimension: CGFloat = 2048, maxBytes: Int = 4 * 1024 * 1024) -> Data? {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: target))
            draw(in: CGRect(origin: .zero, size: target))
        }
        for quality in [0.82, 0.7, 0.58, 0.45] {
            if let data = normalized.jpegData(compressionQuality: quality), data.count <= maxBytes { return data }
        }
        return nil
    }
}

@MainActor @Observable
final class MealVoiceRecorder: NSObject, AVAudioRecorderDelegate {
    var isRecording = false
    var elapsedSeconds = 0
    var errorMessage: String?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var fileURL: URL?

    func start() async {
        errorMessage = nil
        guard await microphoneAllowed() else {
            errorMessage = "Allow microphone access in iOS Settings to describe a meal by voice."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .spokenAudio)
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appending(path: "leafy-meal-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 24_000,
                AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.record(forDuration: 60)
            self.recorder = recorder
            fileURL = url
            elapsedSeconds = 0
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.elapsedSeconds += 1
                    if self.elapsedSeconds >= 60 { _ = self.stop() }
                }
            }
        } catch {
            errorMessage = "Leafy couldn’t start recording. \(error.localizedDescription)"
        }
    }

    @discardableResult func stop() -> URL? {
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        return fileURL
    }

    func cancel() {
        recorder?.stop()
        timer?.invalidate()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        recorder = nil
        timer = nil
        fileURL = nil
        elapsedSeconds = 0
        isRecording = false
    }

    private func microphoneAllowed() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in continuation.resume(returning: allowed) }
        }
    }
}
