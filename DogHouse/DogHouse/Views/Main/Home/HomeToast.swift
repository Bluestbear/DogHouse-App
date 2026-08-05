//
//  HomeToast.swift
//  DogHouse
//

import SwiftUI

/// The floating capsule that drops in at the top of Home for level-ups, belly
/// rubs and roses. Only the contents differ between them, so the chrome lives
/// here rather than being spelled out once per toast.
struct HomeToast<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 4)
    }
}

#Preview {
    VStack(spacing: 12) {
        HomeToast {
            Image(systemName: "star.fill").foregroundStyle(.yellow)
            Text("Fireplace is lit!").font(.dhCaptionBold)
        }
        HomeToast {
            Text("🐾")
            Text("Sam gave you a belly rub!").font(.dhCaptionBold)
            Text("❤️")
        }
    }
}
