//
//  GalleryView.swift
//  Stable Action
//
//  Created by Rudra Shah on 01/03/26.
//

import SwiftUI
import Photos
import AVKit
import Combine

// MARK: - Identifiable URL wrapper (safe alternative to retroactive conformance)

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Gallery View

struct GalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = GalleryViewModel()
    @State private var selectedVideo: IdentifiableURL?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ──
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white, .white.opacity(0.25))
                    }
                    .contentShape(Rectangle())
                    Spacer()
                    Text("Recordings")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 28, height: 28)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if vm.assets.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.35))
                        Text("No recordings yet")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(vm.assets, id: \.localIdentifier) { asset in
                                GalleryThumbnailCell(asset: asset)
                                    .onTapGesture { playVideo(asset: asset) }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
        }
        .onAppear { vm.fetchVideos() }
        .fullScreenCover(item: $selectedVideo) { item in
            VideoPlayerView(url: item.url)
        }
    }

    private func playVideo(asset: PHAsset) {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            guard let urlAsset = avAsset as? AVURLAsset else { return }
            DispatchQueue.main.async {
                selectedVideo = IdentifiableURL(url: urlAsset.url)
            }
        }
    }
}

// MARK: - View Model

final class GalleryViewModel: ObservableObject {
    @Published var assets: [PHAsset] = []

    func fetchVideos() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            loadAssets()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    self?.loadAssets()
                }
            }
        default:
            break
        }
    }

    private func loadAssets() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)

        let results = PHAsset.fetchAssets(with: fetchOptions)
        var fetched: [PHAsset] = []
        results.enumerateObjects { asset, _, _ in
            fetched.append(asset)
        }

        DispatchQueue.main.async {
            self.assets = fetched
        }
    }
}

// MARK: - Thumbnail Cell

struct GalleryThumbnailCell: View {
    let asset: PHAsset
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.08)
                }
            }
            .aspectRatio(3/4, contentMode: .fit)
            .clipped()

            // Duration label
            Text(formattedDuration(asset.duration))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.6))
                .cornerRadius(4)
                .padding(4)
        }
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        let size = CGSize(width: 300, height: 400)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            DispatchQueue.main.async { self.thumbnail = image }
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
