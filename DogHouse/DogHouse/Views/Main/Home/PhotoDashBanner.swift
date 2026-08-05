//
//  PhotoDashBanner.swift
//  DogHouse
//

import SwiftUI
import PhotosUI

/// The app-triggered photo race: first partner to send a picture wins.
///
/// Owns its own camera and library picker state — that was four `@State`
/// properties on HomeView that nothing else on the screen touched, and they
/// only exist while the banner is up.
struct PhotoDashBanner: View {
    let dash: Challenge
    /// Hands back a picked or snapped image; the caller does the upload.
    let onSubmit: (UIImage) -> Void
    /// Surfaced through the screen's error banner.
    let onError: (String) -> Void
    /// Driven by the caller, which owns the upload.
    let isSubmitting: Bool

    @State private var photoPick: PhotosPickerItem?
    @State private var showCameraPicker = false
    @State private var isLoadingPick = false

    var body: some View {
        HStack(spacing: 12) {
            Text("📸").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Photo Dash!").font(.dhBodyBold)
                Text(dash.prompt).font(.dhCaption).foregroundStyle(.secondary)
            }
            Spacer()
            if isSubmitting || isLoadingPick {
                ProgressView()
            } else {
                // Snap with the camera — the true "dash" experience
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCameraPicker = true
                    } label: {
                        Image(systemName: "camera.fill").font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.cozyOrange)
                    .accessibilityLabel("Take a photo")
                }
                // Or pick from the library
                PhotosPicker(selection: $photoPick, matching: .images) {
                    Image(systemName: "photo.on.rectangle").font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.cozyOrange)
                .accessibilityLabel("Choose a photo from your library")
            }
        }
        .padding(14)
        .background(Color.cozyOrange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPicker(onCapture: onSubmit)
                .ignoresSafeArea()
        }
        .onChange(of: photoPick) { _, item in
            guard let item else { return }
            isLoadingPick = true
            Task {
                defer { photoPick = nil; isLoadingPick = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        onError("Couldn't load that photo")
                        return
                    }
                    onSubmit(image)
                } catch {
                    onError(error.localizedDescription)
                }
            }
        }
    }
}
