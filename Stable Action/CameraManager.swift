//
//  CameraManager.swift
//  Stable Action
//
//  Created by Rudra Shah on 26/02/26.
//

import AVFoundation
import Combine
import CoreImage
import Photos
import UIKit

final class CameraManager: NSObject, ObservableObject {

    enum CameraType { case wide, ultraWide, telephoto }

    @Published var cameraType: CameraType = .ultraWide {
        didSet { sessionQueue.async { [weak self] in self?.reconfigureVideoInput() } }
    }

    // MARK: - Session

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var isConfigured = false

    // MARK: - Inputs

    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?

    // MARK: - Data outputs

    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private let dataOutputQueue = DispatchQueue(label: "camera.data.output", qos: .userInteractive)

    // MARK: - Asset writer (all accessed exclusively on dataOutputQueue)

    nonisolated(unsafe) private var assetWriter: AVAssetWriter?
    nonisolated(unsafe) private var videoWriterInput: AVAssetWriterInput?
    nonisolated(unsafe) private var audioWriterInput: AVAssetWriterInput?
    nonisolated(unsafe) private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    nonisolated(unsafe) private var recordingURL: URL?
    nonisolated(unsafe) private var sessionAtSourceTime = false
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Published state

    @Published var permissionDenied = false
    @Published var isRecording = false
    @Published var lastVideoURL: URL?

    nonisolated(unsafe) private var isRecordingFlag = false

    @Published var actionModeEnabled = false {
        didSet { sessionQueue.async { self.applyStabilization() } }
    }

    // MARK: - Providers (called on data-output queue, every frame)

    nonisolated(unsafe) var rollProvider: () -> Double = { 0.0 }
    nonisolated(unsafe) var translationProvider: () -> (Double, Double) = { (0.0, 0.0) }

    // MARK: - Preview frame handler

    /// Set by CameraPreview2. Receives the fully-processed CIImage every frame.
    nonisolated(unsafe) var previewFrameHandler: ((CIImage) -> Void)? = nil

    // MARK: - Crop geometry constants (must match HorizonRectangleView)

    private let cropFraction: Double = 3.0 / 5.0 * 0.90
    private let cropAspectW: Double  = 3.0
    private let cropAspectH: Double  = 4.0

    // MARK: - Lifecycle

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:        checkMicThenStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                if ok { self?.checkMicThenStart() }
                else  { DispatchQueue.main.async { self?.permissionDenied = true } }
            }
        default:
            DispatchQueue.main.async { self.permissionDenied = true }
        }
    }

    private func checkMicThenStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:    startSession()
        case .notDetermined: AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in self?.startSession() }
        default:             startSession()
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured { self.configureSession() }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.isRecording { self.stopRecording() }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // MARK: - Session Configuration

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .inputPriority
        defer { session.commitConfiguration(); isConfigured = true }

        guard let device = selectVideoDevice(for: cameraType, position: .back),
              let input  = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        videoDeviceInput = input

        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus)       { device.focusMode    = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.unlockForConfiguration()

        enforceFourByThreeAndMinZoom()

        if let mic      = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInput(micInput)
            audioDeviceInput = micInput
        }

        videoDataOutput.alwaysDiscardsLateVideoFrames = false
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
        guard session.canAddOutput(videoDataOutput) else { return }
        session.addOutput(videoDataOutput)

        audioDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
        if session.canAddOutput(audioDataOutput) { session.addOutput(audioDataOutput) }

        applyStabilization()
    }

    // MARK: - Stabilization

    private func applyStabilization() {
        guard let conn = videoDataOutput.connection(with: .video) else { return }
        guard conn.isVideoStabilizationSupported else { return }
        if actionModeEnabled {
            if #available(iOS 18.0, *) {
                conn.preferredVideoStabilizationMode = .cinematicExtendedEnhanced
            } else {
                conn.preferredVideoStabilizationMode = .cinematicExtended
            }
        } else {
            conn.preferredVideoStabilizationMode = .auto
        }
    }

    // MARK: - Device selection

    private func selectVideoDevice(for type: CameraType,
                                   position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        switch type {
        case .ultraWide:
            return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: position)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        case .telephoto:
            return AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: position)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        case .wide:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        }
    }

    // MARK: - 4:3 format

    private func best4by3Format(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let target = 4.0 / 3.0
        var best: AVCaptureDevice.Format?; var bestW: Int32 = 0
        for fmt in device.formats {
            let d = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            guard d.width > 0, d.height > 0 else { continue }
            guard abs(Double(d.width) / Double(d.height) - target) < 0.01 else { continue }
            guard fmt.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 30 }) else { continue }
            if d.width > bestW { best = fmt; bestW = d.width }
        }
        return best
    }

    private func enforceFourByThreeAndMinZoom() {
        guard let device = videoDeviceInput?.device else { return }
        session.sessionPreset = .inputPriority
        do {
            try device.lockForConfiguration()
            if let fmt = best4by3Format(for: device) {
                device.activeFormat = fmt
                let dur = CMTime(value: 1, timescale: 30)
                device.activeVideoMinFrameDuration = dur
                device.activeVideoMaxFrameDuration = dur
            }
            if #available(iOS 17.0, *) {
                device.videoZoomFactor = max(1.0, device.minAvailableVideoZoomFactor)
            } else {
                device.videoZoomFactor = 1.0
            }
            device.unlockForConfiguration()
        } catch { print("4:3 config error:", error) }
    }

    private func reconfigureVideoInput() {
        session.beginConfiguration()
        if let old = videoDeviceInput { session.removeInput(old); videoDeviceInput = nil }
        if let dev = selectVideoDevice(for: cameraType, position: .back),
           let inp = try? AVCaptureDeviceInput(device: dev),
           session.canAddInput(inp) {
            session.addInput(inp); videoDeviceInput = inp
            enforceFourByThreeAndMinZoom()
        }
        session.commitConfiguration()
        applyStabilization()
    }

    func setCameraType(_ type: CameraType) {
        DispatchQueue.main.async { self.cameraType = type }
    }

    // MARK: - Focus

    func focusAt(point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self, let dev = self.videoDeviceInput?.device else { return }
            try? dev.lockForConfiguration()
            if dev.isFocusPointOfInterestSupported    { dev.focusPointOfInterest    = point; dev.focusMode    = .autoFocus }
            if dev.isExposurePointOfInterestSupported { dev.exposurePointOfInterest = point; dev.exposureMode = .autoExpose }
            dev.unlockForConfiguration()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, let dev = self.videoDeviceInput?.device else { return }
                try? dev.lockForConfiguration()
                if dev.isFocusModeSupported(.continuousAutoFocus)       { dev.focusMode    = .continuousAutoFocus }
                if dev.isExposureModeSupported(.continuousAutoExposure) { dev.exposureMode = .continuousAutoExposure }
                dev.unlockForConfiguration()
            }
        }
    }

    // MARK: - Recording

    func toggleRecording() {
        if isRecordingFlag {
            dataOutputQueue.async { self.stopRecording() }
        } else {
            sessionQueue.async {
                guard let device = self.videoDeviceInput?.device else { return }
                let dims        = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                let sensorShort = Double(min(dims.width, dims.height))
                let cropW_d     = sensorShort * self.cropFraction
                let cropH_d     = cropW_d * (self.cropAspectH / self.cropAspectW)
                let outW        = max(2, Int(cropW_d) & ~1)
                let outH        = max(2, Int(cropH_d) & ~1)
                self.dataOutputQueue.async { self.startRecording(outW: outW, outH: outH) }
            }
        }
    }

    private func startRecording(outW: Int, outH: Int) {
        guard outW > 0, outH > 0 else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        guard let writer = try? AVAssetWriter(url: url, fileType: .mov) else {
            print("Could not create AVAssetWriter"); return
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  outW,
            AVVideoHeightKey: outH,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:      10_000_000,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        vInput.transform = .identity

        let adaptorAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey           as String: outW,
            kCVPixelBufferHeightKey          as String: outH
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput, sourcePixelBufferAttributes: adaptorAttrs)

        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        aInput.expectsMediaDataInRealTime = true

        if writer.canAdd(vInput) { writer.add(vInput) }
        if writer.canAdd(aInput) { writer.add(aInput) }

        guard writer.startWriting() else {
            print("AssetWriter failed:", writer.error as Any); return
        }

        assetWriter         = writer
        videoWriterInput    = vInput
        audioWriterInput    = aInput
        pixelBufferAdaptor  = adaptor
        recordingURL        = url
        sessionAtSourceTime = false
        isRecordingFlag     = true
        DispatchQueue.main.async { self.isRecording = true }
    }

    private func stopRecording() {
        guard isRecordingFlag, let writer = assetWriter else { return }

        isRecordingFlag    = false
        assetWriter        = nil
        videoWriterInput   = nil
        audioWriterInput   = nil
        pixelBufferAdaptor = nil
        DispatchQueue.main.async { self.isRecording = false }

        let url = recordingURL
        writer.finishWriting {
            guard let url else { return }
            DispatchQueue.main.async { self.lastVideoURL = url }
            self.saveVideoToLibrary(url: url)
        }
    }

    // MARK: - Frame processing

    nonisolated private func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Step 1: orient landscape sensor buffer to portrait
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let pW: CGFloat = ciImage.extent.width
        let pH: CGFloat = ciImage.extent.height

        // Step 2: counter-rotate around the portrait centre by -roll
        let roll:  CGFloat = CGFloat(rollProvider())
        let angle: CGFloat = -roll
        let cx = pW / 2;  let cy = pH / 2

        let centreRotation = CGAffineTransform(translationX: -cx, y: -cy)
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(translationX:  cx, y:  cy))
        let rotated = ciImage.transformed(by: centreRotation)

        // Step 3: crop to 3:4 rect, shifted by the motion-stabilisation translation.
        //
        // Use rotated.extent (larger than original after rotation) so margins are always >= 0.
        let re = rotated.extent
        let shorter: CGFloat = min(pW, pH)
        let cropW: CGFloat   = shorter * CGFloat(cropFraction)
        let cropH: CGFloat   = cropW   * CGFloat(cropAspectH / cropAspectW)

        let marginX = max(0, (re.width  - cropW) / 2)
        let marginY = max(0, (re.height - cropH) / 2)

        // The translation offset is in portrait screen space. Rotate it by the same
        // angle as the image so the shift direction stays aligned with the screen.
        let (normX, normY) = translationProvider()
        let cosA = cos(angle);  let sinA = sin(angle)
        let rotNormX = CGFloat(normX) * cosA - CGFloat(normY) * sinA
        let rotNormY = CGFloat(normX) * sinA + CGFloat(normY) * cosA

        let shiftX = rotNormX * marginX * 0.9
        let shiftY = rotNormY * marginY * 0.9

        let cropRect = CGRect(
            x: re.midX - cropW / 2 + shiftX,
            y: re.midY - cropH / 2 + shiftY,
            width:  cropW,
            height: cropH
        ).integral

        let cropped = rotated
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.minX,
                                               y:            -cropRect.minY))

        // Always deliver to the live preview handler
        previewFrameHandler?(cropped)

        // Step 4: write to file (only when recording)
        guard let writer  = assetWriter,
              let vInput  = videoWriterInput,
              let adaptor = pixelBufferAdaptor,
              writer.status == .writing,
              vInput.isReadyForMoreMediaData else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !sessionAtSourceTime {
            writer.startSession(atSourceTime: pts)
            sessionAtSourceTime = true
        }

        guard let pool = adaptor.pixelBufferPool else { return }
        var outBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuffer) == kCVReturnSuccess,
              let destBuffer = outBuffer else { return }

        let renderW = Int(cropRect.width)  & ~1
        let renderH = Int(cropRect.height) & ~1
        ciContext.render(cropped,
                         to: destBuffer,
                         bounds: CGRect(x: 0, y: 0, width: renderW, height: renderH),
                         colorSpace: CGColorSpaceCreateDeviceRGB())
        adaptor.append(destBuffer, withPresentationTime: pts)
    }

    // MARK: - Save to Photos

    private func saveVideoToLibrary(url: URL) {
        let save = {
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { _, error in
                if let error { print("Video save error:", error) }
            }
        }
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited: save()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { s in
                if s == .authorized || s == .limited { save() }
            }
        default: break
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate + Audio

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate,
                          AVCaptureAudioDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        if output is AVCaptureVideoDataOutput {
            // Always process — CameraPreview2 needs frames even when not recording.
            processVideoFrame(sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            guard isRecordingFlag,
                  let writer = assetWriter,
                  let aInput = audioWriterInput,
                  writer.status == .writing,
                  sessionAtSourceTime,
                  aInput.isReadyForMoreMediaData else { return }
            aInput.append(sampleBuffer)
        }
    }
}
