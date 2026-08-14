import AVFoundation
import SwiftUI
import UIKit

enum BarcodeScannerStatus: Equatable {
    case requestingPermission, ready, denied, unavailable
}

struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    var onStatusChange: (BarcodeScannerStatus) -> Void = { _ in }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        controller.onStatusChange = onStatusChange
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onStatusChange: ((BarcodeScannerStatus) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var didScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        Task { @MainActor in
            onStatusChange?(.requestingPermission)
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: configureCamera()
            case .notDetermined:
                let allowed = await AVCaptureDevice.requestAccess(for: .video)
                if allowed { configureCamera() } else { showUnavailable(status: .denied) }
            case .denied, .restricted: showUnavailable(status: .denied)
            @unknown default: showUnavailable(status: .unavailable)
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    private func configureCamera() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            showUnavailable(status: .unavailable); return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { showUnavailable(status: .unavailable); return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
        onStatusChange?(.ready)
        let guide = UIView()
        guide.layer.borderColor = UIColor.white.cgColor
        guide.layer.borderWidth = 3
        guide.layer.cornerRadius = 18
        guide.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(guide)
        let instruction = UILabel()
        instruction.text = "Center the barcode inside the frame"
        instruction.textColor = .white
        instruction.font = .preferredFont(forTextStyle: .headline)
        instruction.textAlignment = .center
        instruction.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instruction)
        NSLayoutConstraint.activate([
            guide.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            guide.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            guide.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.78),
            guide.heightAnchor.constraint(equalToConstant: 180),
            instruction.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            instruction.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            instruction.bottomAnchor.constraint(equalTo: guide.topAnchor, constant: -24),
        ])
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }

    private func showUnavailable(status: BarcodeScannerStatus) {
        onStatusChange?(status)
        let label = UILabel()
        label.text = status == .denied
            ? "Camera access is off.\nAllow access in Settings or search instead."
            : "Camera scanning isn’t available on this device.\nUse product search instead."
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didScan, let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = readable.stringValue else { return }
        didScan = true
        session.stopRunning()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCode?(code)
    }
}
