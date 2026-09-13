import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession?
    let presentation: CameraPreviewPresentation
    let interfaceChanged: (CameraInterfaceOrientation) -> Void

    func makeUIView(context: Context) -> PreviewSurface {
        let surface = PreviewSurface()
        surface.interfaceChanged = interfaceChanged
        return surface
    }
    func updateUIView(_ view: PreviewSurface, context: Context) {
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
#if DEBUG
            // A session may only feed one preview layer; log every handoff so a second surface
            // taking the session (the Phase 3 black-preview defect) is visible in the console.
            MellowLog.app.info("Preview layer session \(session == nil ? "detached" : "attached", privacy: .public)")
#endif
        }
        view.presentation = presentation
        view.applyPresentation()
    }
    static func dismantleUIView(_ view: PreviewSurface, coordinator: ()) {
#if DEBUG
        MellowLog.app.info("Preview surface dismantled (session was \(view.previewLayer.session == nil ? "nil" : "attached", privacy: .public))")
#endif
        view.previewLayer.session = nil
        view.interfaceChanged = nil
    }

    final class PreviewSurface: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var presentation = CameraPreviewPresentation()
        var interfaceChanged: ((CameraInterfaceOrientation) -> Void)?
        private var lastInterface: UIInterfaceOrientation?

        override func layoutSubviews() {
            super.layoutSubviews()
            applyPresentation()
            reportInterface()
        }
        override func didMoveToWindow() { super.didMoveToWindow(); reportInterface() }
        private func reportInterface() {
            guard let orientation = window?.windowScene?.interfaceOrientation, orientation != lastInterface else { return }
            lastInterface = orientation
            // Report after UIKit's layout pass; never mutate SwiftUI state during updateUIView.
            DispatchQueue.main.async { [weak self] in
                self?.interfaceChanged?(CameraInterfaceOrientation(orientation))
            }
        }
        func applyPresentation() {
            previewLayer.videoGravity = .resizeAspectFill
            guard let connection = previewLayer.connection else { return }
            if connection.isVideoRotationAngleSupported(presentation.angle) {
                connection.videoRotationAngle = presentation.angle
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = presentation.mirrored
            }
        }
    }
}
