import CoreLocation
import Foundation
import OSLog
import Photos
import UIKit

enum WeatherPhotoLibraryError: LocalizedError {
    case authorizationDenied
    case assetCreationFailed
    case albumCreationFailed
    case assetLookupFailed
    case imageDecodeFailed

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "没有相册权限，无法保存到系统相册。"
        case .assetCreationFailed:
            "照片未能写入系统相册。"
        case .albumCreationFailed:
            "无法创建或访问 WeatherMood365 相簿。"
        case .assetLookupFailed:
            "无法定位刚保存到系统相册的照片。"
        case .imageDecodeFailed:
            "无法读取要保存的照片。"
        }
    }
}

struct PhotoLibrarySyncResult {
    var savedToLibrary: Bool
    var addedToWeatherMoodAlbum: Bool
    var warningMessage: String?
}

struct WeatherMoodAlbumHandle {
    let localIdentifier: String
}

actor WeatherPhotoLibraryService {
    static let shared = WeatherPhotoLibraryService()

    static let albumName = "WeatherMood365"
    static let syncToLibraryEnabledKey = "savePhotoCopyToSystemLibrary"

    private let logger = Logger(subsystem: "com.han.WeatherMood365", category: "photo-library")

    private init() {}

    func savePhoto(data: Data, date: Date, location: PhotoLocation?) async throws -> PhotoLibrarySyncResult {
        guard UIImage(data: data) != nil else {
            logger.error("Failed to decode image before syncing to photo library")
            throw WeatherPhotoLibraryError.imageDecodeFailed
        }

        let localIdentifier = try await saveAssetToPhotoLibrary(data: data, date: date, location: location)

        do {
            let album = try await ensureWeatherMoodAlbum()
            try await addAsset(localIdentifier: localIdentifier, to: album)
            return PhotoLibrarySyncResult(
                savedToLibrary: true,
                addedToWeatherMoodAlbum: true,
                warningMessage: nil
            )
        } catch {
            logger.error("Photo saved to library but failed to add into dedicated album: \(error.localizedDescription, privacy: .public)")
            return PhotoLibrarySyncResult(
                savedToLibrary: true,
                addedToWeatherMoodAlbum: false,
                warningMessage: "已保存到系统相册，但未归档到 WeatherMood365 相簿：\(error.localizedDescription)"
            )
        }
    }

    func saveAssetToPhotoLibrary(data: Data, date: Date, location: PhotoLocation?) async throws -> String {
        let status = await requestAddOnlyAuthorization()
        guard status == .authorized || status == .limited else {
            logger.error("Photo library add-only authorization denied with status: \(String(describing: status.rawValue))")
            throw WeatherPhotoLibraryError.authorizationDenied
        }

        logger.log("Creating photo library asset with add-only authorization")
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let identifierBox = PhotoLibraryIdentifierBox()

            PHPhotoLibrary.shared().performChanges {
                let assetRequest = PHAssetCreationRequest.forAsset()
                assetRequest.creationDate = date
                assetRequest.addResource(with: .photo, data: data, options: nil)

                if let location {
                    assetRequest.location = CLLocation(latitude: location.latitude, longitude: location.longitude)
                }

                identifierBox.value = assetRequest.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { success, error in
                if let error {
                    self.logger.error("Failed to create asset in system photo library: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                } else if success, let createdIdentifier = identifierBox.value {
                    self.logger.log("Created photo library asset: \(createdIdentifier, privacy: .public)")
                    continuation.resume(returning: createdIdentifier)
                } else {
                    self.logger.error("Photo library asset creation finished without placeholder identifier")
                    continuation.resume(throwing: WeatherPhotoLibraryError.assetCreationFailed)
                }
            }
        }
    }

    func ensureWeatherMoodAlbum() async throws -> WeatherMoodAlbumHandle {
        let status = await requestReadWriteAuthorization()
        guard status == .authorized || status == .limited else {
            logger.error("Photo library read-write authorization denied with status: \(String(describing: status.rawValue))")
            throw WeatherPhotoLibraryError.authorizationDenied
        }

        if let album = Self.fetchAlbum() {
            logger.log("Using existing WeatherMood365 album: \(album.localIdentifier, privacy: .public)")
            return WeatherMoodAlbumHandle(localIdentifier: album.localIdentifier)
        }

        logger.log("Creating WeatherMood365 album")
        let albumIdentifier = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let identifierBox = PhotoLibraryIdentifierBox()

            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                    withTitle: Self.albumName
                )
                identifierBox.value = request.placeholderForCreatedAssetCollection.localIdentifier
            } completionHandler: { success, error in
                if let error {
                    self.logger.error("Failed to create WeatherMood365 album: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                } else if success, let createdIdentifier = identifierBox.value {
                    continuation.resume(returning: createdIdentifier)
                } else {
                    continuation.resume(throwing: WeatherPhotoLibraryError.albumCreationFailed)
                }
            }
        }

        logger.log("Created WeatherMood365 album: \(albumIdentifier, privacy: .public)")
        return WeatherMoodAlbumHandle(localIdentifier: albumIdentifier)
    }

    func addAsset(localIdentifier: String, to album: WeatherMoodAlbumHandle) async throws {
        guard let asset = fetchAsset(with: localIdentifier) else {
            logger.error("Failed to fetch saved asset before adding to album: \(localIdentifier, privacy: .public)")
            throw WeatherPhotoLibraryError.assetLookupFailed
        }

        guard let albumCollection = fetchAlbum(with: album.localIdentifier) else {
            logger.error("Failed to fetch WeatherMood365 album before adding asset: \(album.localIdentifier, privacy: .public)")
            throw WeatherPhotoLibraryError.albumCreationFailed
        }

        logger.log("Adding asset \(localIdentifier, privacy: .public) to WeatherMood365 album")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                guard let request = PHAssetCollectionChangeRequest(for: albumCollection) else {
                    return
                }
                request.addAssets([asset] as NSArray)
            } completionHandler: { success, error in
                if let error {
                    self.logger.error("Failed to add asset to WeatherMood365 album: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                } else if success {
                    self.logger.log("Added asset to WeatherMood365 album successfully")
                    continuation.resume()
                } else {
                    continuation.resume(throwing: WeatherPhotoLibraryError.albumCreationFailed)
                }
            }
        }
    }

    private func requestAddOnlyAuthorization() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if current == .notDetermined {
            logger.log("Requesting add-only photo library authorization")
            return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }

        logger.log("Using existing add-only authorization status: \(String(describing: current.rawValue))")
        return current
    }

    private func requestReadWriteAuthorization() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .notDetermined {
            logger.log("Requesting read-write photo library authorization for album access")
            return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }

        logger.log("Using existing read-write authorization status: \(String(describing: current.rawValue))")
        return current
    }

    private nonisolated func fetchAsset(with localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    private nonisolated func fetchAlbum(with localIdentifier: String) -> PHAssetCollection? {
        PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    private nonisolated static func fetchAlbum() -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
        return PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: fetchOptions
        ).firstObject
    }
}

private final class PhotoLibraryIdentifierBox: @unchecked Sendable {
    var value: String?
}
