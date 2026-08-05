//
//  LoginView.swift
//  DogHouse
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var showError = false
    @State private var errorText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 50))
                        .foregroundStyle(Color.dogHouseBrown)
                    Text("Welcome Back")
                        .font(.dhScreenTitle)
                }
                .padding(.top, 20)

                // Form fields
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                }
                .padding(.horizontal, 24)

                // Log In button
                Button {
                    Task { await logIn() }
                } label: {
                    Group {
                        if authService.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Log In")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(formIsValid ? Color.dogHouseBrown : Color.gray.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!formIsValid || authService.isLoading)
                .padding(.horizontal, 24)

                if showError {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                }

                SocialSignInButtons(onLightBackground: true)
                    .padding(.horizontal, 24)
            }
        }
        .navigationTitle("Log In")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Validation

    private var formIsValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
        && email.contains("@")
        && password.count >= 6
    }

    // MARK: - Actions

    private func logIn() async {
        showError = false
        do {
            try await authService.signIn(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
        } catch {
            errorText = AuthService.friendlyError(error)
            showError = true
        }
    }
}

#Preview {
    NavigationStack {
        LoginView()
            .environmentObject(AuthService())
    }
}
