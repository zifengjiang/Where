import SwiftUI
import UIKit

enum AsyncImageFailurePolicy: Equatable {
    case compact
    case retryable

    var allowsRetry: Bool { self == .retryable }
}

struct AsyncImageFileView<Content: View>: View {
    enum FailureStyle { case compact, location }

    let relativePath: String?
    let imageStore: any SceneImageStoreProtocol
    let maxPixelSize: Int
    let accessibilityLabel: String
    var failureStyle: FailureStyle = .compact
    var failurePolicy: AsyncImageFailurePolicy = .retryable
    @ViewBuilder let content: (UIImage) -> Content

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var retryToken = 0

    var body: some View {
        Group {
            if let image {
                content(image).accessibilityLabel(accessibilityLabel)
            } else if isLoading {
                ZStack {
                    Color.orange.opacity(0.10)
                    ProgressView().accessibilityLabel("正在载入照片")
                }
            } else {
                ZStack {
                    Color.orange.opacity(0.10)
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(failureStyle == .location ? .title : .body)
                        Text("照片不可用").font(.subheadline)
                        if failurePolicy.allowsRetry {
                            Button("重试") { retryToken += 1 }.font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(accessibilityLabel)，照片不可用")
            }
        }
        .task(id: LoadIdentity(path: relativePath, retryToken: retryToken, maxPixelSize: maxPixelSize)) {
            await load()
        }
    }

    private func load() async {
        image = nil
        isLoading = true
        guard let relativePath,
              let asset = await imageStore.loadImageAsset(relativePath: relativePath),
              !Task.isCancelled else {
            if !Task.isCancelled { isLoading = false }
            return
        }
        let decoded = await SceneThumbnailCache.shared.thumbnail(
            path: relativePath,
            asset: asset,
            maxPixelSize: maxPixelSize
        )?.image
        guard !Task.isCancelled else { return }
        image = decoded
        isLoading = false
    }

    private struct LoadIdentity: Equatable {
        let path: String?
        let retryToken: Int
        let maxPixelSize: Int
    }
}

extension AsyncImageFileView where Content == Image {
    init(relativePath: String?, imageStore: any SceneImageStoreProtocol, maxPixelSize: Int,
         accessibilityLabel: String, failureStyle: FailureStyle = .compact) {
        self.init(relativePath: relativePath, imageStore: imageStore, maxPixelSize: maxPixelSize,
                  accessibilityLabel: accessibilityLabel, failureStyle: failureStyle) {
            Image(uiImage: $0)
        }
    }
}
