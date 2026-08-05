//
//  SocialSignInButtons.swift
//  DogHouse
//
//  Sign in with Apple / Google. Both providers land in the same place as email
//  sign-up: AuthService.bootstrapProfileIfNeeded creates the profile, the
//  private document and the pairing code on first sign-in, so an account
//  created here is indistinguishable from one created with a password.
//

import SwiftUI
import AuthenticationServices

struct SocialSignInButtons: View {
    @EnvironmentObject var authService: AuthService

    /// Light content sits on the orange Welcome gradient; the auth forms are on
    /// a system background and need the opposite treatment.
    var onLightBackground = false

    @State private var showError = false
    @State private var errorText = ""
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 12) {
            divider

            SignInWithAppleButton(.signIn) { request in
                authService.prepareAppleRequest(request)
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(onLightBackground ? .black : .white)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(isWorking)

            // Hidden until Google is enabled for this app in the Firebase
            // console — without CLIENT_ID there is nothing to sign in against,
            // and a button that always errors is worse than no button.
            if AuthService.isGoogleSignInConfigured {
                Button {
                    signInWithGoogle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "globe")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Sign in with Google")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(googleBackground)
                    .foregroundStyle(onLightBackground ? Color.primary : Color.dogHouseBrown)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.primary.opacity(onLightBackground ? 0.15 : 0), lineWidth: 1)
                    )
                }
                .disabled(isWorking)
            }

            if showError {
                Text(errorText)
                    .font(.dhCaption)
                    .foregroundStyle(onLightBackground ? .red : .white)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var googleBackground: Color {
        onLightBackground ? Color(.systemBackground) : .white
    }

    private var divider: some View {
        HStack(spacing: 12) {
            line
            Text("or")
                .font(.dhCaption)
                .foregroundStyle(onLightBackground ? Color.secondary : Color.white.opacity(0.8))
            line
        }
    }

    private var line: some View {
        Rectangle()
            .fill(onLightBackground ? Color(.systemGray4) : Color.white.opacity(0.4))
            .frame(height: 1)
    }

    // MARK: - Actions

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        showError = false
        switch result {
        case .success(let authorization):
            isWorking = true
            Task {
                defer { isWorking = false }
                do {
                    try await authService.completeAppleSignIn(authorization)
                    HapticService.shared.success()
                } catch {
                    present(error)
                }
            }
        case .failure(let error):
            // Tapping Cancel is a normal outcome, not something to shout about.
            guard (error as? ASAuthorizationError)?.code != .canceled else { return }
            present(error)
        }
    }

    private func signInWithGoogle() {
        showError = false
        guard let presenter = UIApplication.shared.topViewController else {
            errorText = "Couldn't open Google sign-in. Please try again."
            showError = true
            return
        }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await authService.signInWithGoogle(presenting: presenter)
                HapticService.shared.success()
            } catch {
                // The SDK reports a user-cancelled flow as an error too.
                guard !isCancellation(error) else { return }
                present(error)
            }
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "com.google.GIDSignIn" && nsError.code == -5
    }

    private func present(_ error: Error) {
        errorText = AuthService.friendlyError(error)
        showError = true
        HapticService.shared.error()
    }
}

// MARK: - Presenting View Controller

extension UIApplication {
    /// The view controller Google Sign-In should present from.
    var topViewController: UIViewController? {
        let root = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController

        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
