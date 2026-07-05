//
//  LoadingOverlay.swift
//  DogHouse
//

import SwiftUI

struct LoadingOverlay: View {
    var message: String = "Loading..."

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)

                Text(message)
                    .font(.dhBody)
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

/// Modifier to show inline error banners that auto-dismiss
struct ErrorBanner: ViewModifier {
    @Binding var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(message)
                            .font(.dhCaption)
                            .foregroundStyle(.white)
                        Spacer()
                        Button {
                            withAnimation { errorMessage = nil }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        // Auto-dismiss after 5 seconds
                        Task {
                            try? await Task.sleep(for: .seconds(5))
                            withAnimation { errorMessage = nil }
                        }
                    }
                }
            }
            .animation(.spring(duration: 0.3), value: errorMessage)
    }
}

extension View {
    func errorBanner(_ errorMessage: Binding<String?>) -> some View {
        modifier(ErrorBanner(errorMessage: errorMessage))
    }
}
