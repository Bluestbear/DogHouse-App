//
//  PhotoLibrarySaver.swift
//  DogHouse
//
//  Saves a Photo Dash picture to the user's library (a Premium perk).
//  Add-only access: DogHouse never reads the library, it only drops the
//  photo in, which is the narrowest permission iOS offers
//  (NSPhotoLibraryAddUsageDescription).
//

import Foundation
import Photos

enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case notAllowed
        case badImage

        var errorDescription: String? {
            switch self {
            case .notAllowed: "DogHouse isn't allowed to add photos. You can change that in Settings › Privacy › Photos."
            case .badImage: "That photo couldn't be read."
            }
        }
    }

    /// Adds the base64 JPEG a Photo Dash stores to the photo library.
    static func save(base64 photoData: String) async throws {
        guard let data = Data(base64Encoded: photoData) else { throw SaveError.badImage }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.notAllowed }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }
}
