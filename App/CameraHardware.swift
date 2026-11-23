import AVFoundation
import CoreImage
import ImageIO
import SwiftUI
import UIKit

/// 真正操纵 iPhone 摄像头的部分。只有视频输入，没有麦克风输入。
final class CameraHardware: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                            AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    var onStarted: ((Bool) -> Void)?
    var onSample: ((Data, [UInt8]) -> Void)?
    var onPhoto: ((Data?) -> Void)?
    var onFacing: ((Bool) -> Void)?

    private let sessionQueue = DispatchQueue(label: "ai.camera.session")
    private let videoQueue = DispatchQueue(label: "ai.camera.frames")
    private let imageContext = CIContext(options: [.useSoftwareRenderer: false])
    private let stillOutput = AVCapturePhotoOutput()
    private let frameOutput = AVCaptureVideoDataOutput()
    private let guardLock = NSLock()
    private var cameraInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var position: AVCaptureDevice.Position = .back
    private var shooting = false
    private var frameGate = CameraFrameGate()
    private var lastCheckedAt = 0.0
    private var latestSignature: [UInt8]?
    private var latestAt = 0.0

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                do { try self.configure() } catch {
                    self.onStarted?(false)
                    return
                }
            }
            self.videoQueue.sync { self.frameGate.reset(); self.lastCheckedAt = 0 }
            if !self.session.isRunning { self.session.startRunning() }
            self.onStarted?(self.session.isRunning)
        }
    }

    private func configure() throws {
        // 通话由你原本的 VoIP/WebRTC 实现管理。相机不改它的 AVAudioSession。
        session.automaticallyConfiguresApplicationAudioSession = false
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video, position: position) else {
            throw NSError(domain: "Camera", code: 1)
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw NSError(domain: "Camera", code: 2) }
        session.addInput(input)
        cameraInput = input
        guard session.canAddOutput(stillOutput), session.canAddOutput(frameOutput) else {
            throw NSError(domain: "Camera", code: 3)
        }
        session.addOutput(stillOutput)
        frameOutput.alwaysDiscardsLateVideoFrames = true
        frameOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        frameOutput.setSampleBufferDelegate(self, queue: videoQueue)
        session.addOutput(frameOutput)
        configureMirroring()
        isConfigured = true
    }

    private func configureMirroring() {
        for connection in [frameOutput.connection(with: .video), stillOutput.connection(with: .video)] {
            guard let connection else { continue }
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position == .front
            }
        }
    }

    func flip() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.shooting,
                  let previous = self.cameraInput else { return }
            let next: AVCaptureDevice.Position = self.position == .back ? .front : .back
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video, position: next),
                  let input = try? AVCaptureDeviceInput(device: camera) else { return }
            self.session.beginConfiguration()
            self.session.removeInput(previous)
            let accepted = self.session.canAddInput(input)
            if accepted { self.session.addInput(input) } else { self.session.addInput(previous) }
            self.session.commitConfiguration()
            guard accepted else { return }
            self.cameraInput = input
            self.position = next
            self.configureMirroring()
            self.videoQueue.sync { self.frameGate.reset(); self.lastCheckedAt = 0 }
            self.guardLock.lock()
            self.latestSignature = nil
            self.latestAt = 0
            self.guardLock.unlock()
            self.onFacing?(next == .front)
        }
    }

    func shoot() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning, !self.shooting else { return }
            self.shooting = true
            let options: AVCapturePhotoSettings
            if self.stillOutput.availablePhotoCodecTypes.contains(.jpeg) {
                options = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                options = AVCapturePhotoSettings()
            }
            options.photoQualityPrioritization = .balanced
            options.flashMode = .off
            self.stillOutput.capturePhoto(with: options, delegate: self)
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            self.videoQueue.sync { self.frameGate.reset(); self.lastCheckedAt = 0 }
            self.guardLock.lock()
            self.latestSignature = nil
            self.latestAt = 0
            self.guardLock.unlock()
        }
    }

    func sceneStillSimilar(to signature: [UInt8]) -> Bool {
        guardLock.lock()
        let recent = latestSignature, sampledAt = latestAt
        guardLock.unlock()
        guard let recent, ProcessInfo.processInfo.systemUptime - sampledAt <= 2.5 else { return false }
        return CameraFrameGate.difference(signature, recent) < 0.30
    }

    private func tinySignature(_ pixel: CVPixelBuffer) -> [UInt8]? {
        guard CVPixelBufferGetPixelFormatType(pixel) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pixel, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
        guard let ptr = CVPixelBufferGetBaseAddress(pixel) else { return nil }
        let pixels = ptr.assumingMemoryBound(to: UInt8.self)
        let side = CameraFrameGate.side
        let w = CVPixelBufferGetWidth(pixel), h = CVPixelBufferGetHeight(pixel)
        guard w >= side, h >= side else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(pixel)
        var tiny = [UInt8](repeating: 0, count: side * side)
        for row in 0..<side {
            for col in 0..<side {
                let x = min(w-1, (2*col+1)*w/(2*side))
                let y = min(h-1, (2*row+1)*h/(2*side))
                let i = y * stride + x * 4 // BGRA
                tiny[row*side+col] = UInt8((29*Int(pixels[i]) + 150*Int(pixels[i+1]) + 77*Int(pixels[i+2]))>>8)
            }
        }
        return tiny
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCheckedAt > 0.4, let pixel = CMSampleBufferGetImageBuffer(sampleBuffer),
              let signature = tinySignature(pixel) else { return }
        lastCheckedAt = now
        let shouldSend = frameGate.shouldSample(signature, at: now)
        guardLock.lock()
        latestSignature = signature
        latestAt = now
        guardLock.unlock()
        guard shouldSend else { return }

        var image = CIImage(cvPixelBuffer: pixel)
        let maxEdge = max(image.extent.width, image.extent.height)
        guard maxEdge > 0 else { return }
        image = image.transformed(by: .init(scaleX: min(1.0, 512/maxEdge), y: min(1.0, 512/maxEdge)))
        let compressionKey = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        guard let sample = imageContext.jpegRepresentation(of: image,
                        colorSpace: CGColorSpaceCreateDeviceRGB(), options: [compressionKey: 0.45]),
              sample.count <= 110_000 else { return }
        frameGate.didSend(at: now)
        onSample?(sample, signature)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.shooting = false
            self.onPhoto?(data)
        }
    }
}

/// SwiftUI 中的真实后摄 / 前摄预览，而不是网页里的相机假图。
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let front: Bool

    final class BackedView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var cameraLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    private func mirror(_ layer: AVCaptureVideoPreviewLayer) {
        guard let connection = layer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = front
    }
    func makeUIView(context: Context) -> BackedView {
        let view = BackedView()
        view.cameraLayer.videoGravity = .resizeAspectFill
        view.cameraLayer.session = session
        mirror(view.cameraLayer)
        return view
    }
    func updateUIView(_ view: BackedView, context: Context) {
        if view.cameraLayer.session !== session { view.cameraLayer.session = session }
        mirror(view.cameraLayer)
    }
}
