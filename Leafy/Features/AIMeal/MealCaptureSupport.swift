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
