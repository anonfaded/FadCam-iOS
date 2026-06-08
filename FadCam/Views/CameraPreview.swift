import SwiftUI
import UIKit
import AVFoundation

class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .black
        self.clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.backgroundColor = .black
        self.clipsToBounds = true
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var isMirrored: Bool = false

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.videoPreviewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        view.videoPreviewLayer.connection?.isVideoMirrored = isMirrored
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.connection?.isVideoMirrored = isMirrored
    }
}
