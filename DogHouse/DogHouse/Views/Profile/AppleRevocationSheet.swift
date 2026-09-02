//
//  AppleRevocationSheet.swift
//  DogHouse
//
//  Account deletion for Sign in with Apple users. Apple requires the app to
//  revoke its Sign in with Apple token when such an account is deleted, and
//  revocation needs a fresh authorization code — which only Apple's own sheet
//  can produce. So: one more tap through Apple, then the deletion proceeds.
//
//  The user's right to delete comes first. If Apple's sheet fails, the
//  deletion can still go ahead without the revocation step.
//

import SwiftUI
import AuthenticationServices

struct AppleRevocationSheet: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    /// Called with Apple's authorization code, or nil if the user chose to
    /// delete without revoking after the Apple step failed.
    let onContinue: (String?) -> Void

    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "apple.logo")
                    .font(.system(size: 48))

                VStack(spacing: 10) {
                    Text("One more step")
                        .font(.dhTitle)
                    Text("You signed in with Apple, so Apple asks us to disconnect your Apple ID from DogHouse as part of deleting your account. Confirm with Apple and the deletion will go ahead.")
                        .font(.dhBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                Spacer()

                VStack(spacing: 12) {
                    SignInWithAppleButton(.continue) { request in
                        authService.prepareAppleRequest(request)
                    } onCompletion: { result in
                        handle(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    if let errorText {
                        Text(errorText)
                            .font(.dhCaption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)

                        Button("Delete without this step", role: .destructive) {
                            dismiss()
                            onContinue(nil)
                        }
                        .font(.dhCaptionBold)
                    }

                    Button("Cancel") { dismiss() }
                        .font(.dhCaption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            let code = (authorization.credential as? ASAuthorizationAppleIDCredential)?
                .authorizationCode
                .flatMap { String(data: $0, encoding: .utf8) }
            guard let code else {
                errorText = "Apple didn't return a usable code. You can still delete your account."
                return
            }
            dismiss()
            onContinue(code)
        case .failure(let error):
            guard (error as? ASAuthorizationError)?.code != .canceled else { return }
            errorText = AuthService.friendlyError(error)
        }
    }
}

#Preview {
    AppleRevocationSheet { _ in }
        .environmentObject(AuthService())
}
