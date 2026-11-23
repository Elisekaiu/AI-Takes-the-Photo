import Foundation
import Photos
import UIKit

/// 原片先保留；聊天用的小图是可选的副产品。
enum PhotoVault {
    struct Saved: Sendable {
        let url: URL
        let original: Data
    }

    static func saveOriginal(_ bytes: Data) throws -> Saved {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AI-Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let extensionName = bytes.starts(with: [0xFF, 0xD8, 0xFF]) ? "jpg" : "heic"
        let url = folder.appendingPathComponent("photo-\(UUID().uuidString).\(extensionName)")
        try bytes.write(to: url, options: .atomic)
        return Saved(url: url, original: bytes)
    }

    static func saveToPhotos(_ photo: Saved) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let authorization: PHAuthorizationStatus
        if status == .notDetermined { authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly) }
        else { authorization = status }
        guard authorization == .authorized || authorization == .limited else {
            throw NSError(domain: "Photos", code: 1, userInfo: [NSLocalizedDescriptionKey: "需要允许保存到相册"])
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: photo.original, options: nil)
        }
    }
}
