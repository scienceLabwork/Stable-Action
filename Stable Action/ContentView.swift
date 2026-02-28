//
//  ContentView.swift
//  Stable Action
//
//  Created by Rudra Shah on 26/02/26.
//

import SwiftUI
import AVKit

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var motion = MotionManager()
    @State private var showingPlayer = false
    @State private var focusPoint: CGPoint? = nil
    @State private var focusVisible = false
    @State private var focusID = UUID()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                ZStack {

                    // ── Both preview layers always exist — toggle with opacity ──
                    // Normal mode: plain full-frame camera preview
                    CameraPreview(session: camera.session) { vp, dp in
                        setFocus(view: vp, device: dp)
                    }
                    .opacity(camera.actionModeEnabled ? 0 : 1)
                    .zIndex(camera.actionModeEnabled ? 0 : 1)

                    // Action mode: stabilised horizon-crop pipeline
                    CameraPreview2(camera: camera) { vp, dp in
                        setFocus(view: vp, device: dp)
                    }
                    .opacity(camera.actionModeEnabled ? 1 : 0)
                    .zIndex(camera.actionModeEnabled ? 1 : 0)

                    // ── Overlays (always on top) ──────────────────────────
                    if focusVisible, let pt = focusPoint {
                        FocusSquare(onFinished: { focusVisible = false })
                            .id(focusID)
                            .position(pt)
                            .allowsHitTesting(false)
                    }

                    // Recording indicator
                    if camera.isRecording {
                        VStack {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                    .animation(
                                        .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                                        value: camera.isRecording
                                    )
                                Text("REC")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.45))
                            .clipShape(Capsule())
                            .padding(.top, 14)
                            Spacer()
                        }
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .animation(.easeInOut(duration: 0.35), value: camera.actionModeEnabled)
                .animation(.easeInOut(duration: 0.25), value: camera.isRecording)

                // ── Bottom controls ───────────────────────────────────────
                VStack(spacing: 16) {

                    HStack {
                        // Thumbnail
                        Button {
                            if camera.lastVideoURL != nil { showingPlayer = true }
                        } label: {
                            VideoThumbnailView(url: camera.lastVideoURL)
                                .frame(width: 54, height: 54)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                                )
                        }

                        Spacer()

                        // Record button
                        Button { camera.toggleRecording() } label: {
                            RecordButton(isRecording: camera.isRecording)
                        }

                        Spacer()

                        Color.clear.frame(width: 54, height: 54)
                    }
                    .padding(.horizontal, 24)

                    // Action Mode toggle
                    LiquidGlassActionToggle(isOn: $camera.actionModeEnabled)
                        .padding(.horizontal, 32)
                }
                .padding(.vertical, 18)
            }

            // Permission denied overlay
            if camera.permissionDenied {
                VStack(spacing: 12) {
                    Text("Camera access required")
                        .font(.headline).foregroundStyle(.white)
                    Text("Settings \u{2192} Privacy \u{2192} Camera \u{2192} enable Stable Action.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .padding()
            }
        }
        .onAppear {
            // Wire the thread-safe snapshot provider for the frame pipeline
            camera.motionSnapshotProvider = { [weak motion] in
                motion?.snapshot() ?? (0, 0, 0)
            }
            // Keep legacy providers for backwards compatibility
            camera.rollProvider = { [weak motion] in motion?.roll ?? 0.0 }
            camera.translationProvider = { [weak motion] in
                (motion?.offsetX ?? 0.0, motion?.offsetY ?? 0.0)
            }
            camera.start()
            motion.start()
        }
        .onDisappear { camera.stop(); motion.stop() }
        .fullScreenCover(isPresented: $showingPlayer) {
            if let url = camera.lastVideoURL {
                VideoPlayerView(url: url, isPresented: $showingPlayer)
            }
        }
    }

    // MARK: - Helpers

    private func setFocus(view vp: CGPoint, device dp: CGPoint) {
        focusPoint  = vp
        focusID     = UUID()
        focusVisible = true
        camera.focusAt(point: dp)
    }
}

// MARK: - Record Button

private struct RecordButton: View {
    let isRecording: Bool
    var body: some View {
        ZStack {
            Circle().strokeBorder(.white, lineWidth: 5).frame(width: 78, height: 78)
            if isRecording {
                RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 30, height: 30)
            } else {
                Circle().fill(.red).frame(width: 60, height: 60)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isRecording)
    }
}

// MARK: - Video Thumbnail

private struct VideoThumbnailView: View {
    let url: URL?
    var body: some View {
        Group {
            if let url, let thumb = generateThumbnail(url: url) {
                Image(uiImage: thumb).resizable().scaledToFill()
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                    )
            } else {
                RoundedRectangle(cornerRadius: 0).fill(.white.opacity(0.15))
                    .overlay(Image(systemName: "video.fill").foregroundStyle(.white.opacity(0.5)))
            }
        }
    }
    private func generateThumbnail(url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen   = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 120, height: 120)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        var result: UIImage?
        let sem = DispatchSemaphore(value: 0)
        gen.generateCGImageAsynchronously(for: time) { cg, _, _ in
            if let cg { result = UIImage(cgImage: cg) }
            sem.signal()
        }
        sem.wait()
        return result
    }
}

// MARK: - Full-screen Video Player

struct VideoPlayerView: View {
    let url: URL
    @Binding var isPresented: Bool
    @State private var player: AVPlayer?
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player { VideoPlayer(player: player).ignoresSafeArea() }
            Button {
                player?.pause(); isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding(20)
            }
        }
        .onAppear  { let p = AVPlayer(url: url); player = p; p.play() }
        .onDisappear { player?.pause() }
    }
}

// MARK: - Focus Square

private struct FocusSquare: View {
    var onFinished: (() -> Void)? = nil
    @State private var scale: CGFloat = 1.4
    @State private var opacity: Double = 1.0
    @State private var lineOpacity: Double = 1.0
    private let size: CGFloat = 76
    private let cornerLen: CGFloat = 14
    var body: some View {
        ZStack {
            CornerBrackets(size: size, cornerLen: cornerLen)
                .foregroundStyle(.yellow).opacity(lineOpacity)
            Circle().fill(.yellow.opacity(0.6)).frame(width: 5, height: 5).opacity(lineOpacity)
        }
        .frame(width: size, height: size)
        .scaleEffect(scale).opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { scale = 1.0 }
            withAnimation(.easeOut(duration: 0.25).delay(0.9))            { lineOpacity = 0.45 }
            withAnimation(.easeOut(duration: 0.3 ).delay(1.4))            { opacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.75)        { onFinished?() }
        }
    }
}

private struct CornerBrackets: Shape {
    let size: CGFloat; let cornerLen: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path(); let r = rect; let c = cornerLen
        p.move(to: .init(x: r.minX, y: r.minY+c)); p.addLine(to: .init(x: r.minX, y: r.minY)); p.addLine(to: .init(x: r.minX+c, y: r.minY))
        p.move(to: .init(x: r.maxX-c, y: r.minY)); p.addLine(to: .init(x: r.maxX, y: r.minY)); p.addLine(to: .init(x: r.maxX, y: r.minY+c))
        p.move(to: .init(x: r.maxX, y: r.maxY-c)); p.addLine(to: .init(x: r.maxX, y: r.maxY)); p.addLine(to: .init(x: r.maxX-c, y: r.maxY))
        p.move(to: .init(x: r.minX+c, y: r.maxY)); p.addLine(to: .init(x: r.minX, y: r.maxY)); p.addLine(to: .init(x: r.minX, y: r.maxY-c))
        return p
    }
}

#Preview { ContentView() }
