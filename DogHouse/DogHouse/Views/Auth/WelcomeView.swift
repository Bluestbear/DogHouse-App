//
//  WelcomeView.swift
//  DogHouse
//
//  The single entry screen: Log In and Sign Up share one form, toggled by a
//  segmented picker, with Apple/Google offered once underneath. Both modes and
//  both social providers land in the same place — an account with no display
//  name — so OnboardingContainerView's username step is the one and only place
//  a name is collected. Sign-up therefore asks for email and password only.
//

import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var authService: AuthService

    private enum Mode: String, CaseIterable {
        case logIn = "Log In"
        case signUp = "Sign Up"
    }

    @State private var mode: Mode = .logIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showError = false
    @State private var errorText = ""
    @State private var resetNotice: String?
    @State private var isSendingReset = false
    @FocusState private var focusedField: Field?

    private enum Field { case email, password, confirmPassword }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.cozyOrange.opacity(0.8), Color.dogHouseBrown],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    header
                    card
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            houseIllustration
                .frame(height: 130)

            Text("DogHouse")
                .font(.dhDisplay)
                .foregroundStyle(.white)

            Text("Messed up? You're in the DogHouse. 🐕")
                .font(.dhBody)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 48)
    }

    private var houseIllustration: some View {
        ZStack {
            // Roof
            Triangle()
                .fill(Color.dogHouseBrown)
                .frame(width: 120, height: 60)
                .offset(y: -15)

            // House body
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.dogHouseBrown.opacity(0.8))
                .frame(width: 98, height: 75)
                .offset(y: 22)

            // Door
            UnevenRoundedRectangle(
                topLeadingRadius: 19,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 19
            )
            .fill(Color.black.opacity(0.6))
            .frame(width: 38, height: 45)
            .offset(y: 37)
        }
    }

    // MARK: - Form card

    private var card: some View {
        VStack(spacing: 20) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, _ in
                // A stale "Incorrect password" hanging over the Sign Up form
                // reads as a rejection of a form the user hasn't submitted yet.
                showError = false
                resetNotice = nil
                confirmPassword = ""
            }

            VStack(spacing: 14) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(mode == .signUp ? .next : .go)
                    .onSubmit {
                        if mode == .signUp {
                            focusedField = .confirmPassword
                        } else {
                            Task { await submit() }
                        }
                    }

                if mode == .signUp {
                    SecureField("Confirm Password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .confirmPassword)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                } else {
                    // A forgotten password used to be a dead end: no way back
                    // into the account short of making a new one.
                    HStack {
                        Spacer()
                        Button(isSendingReset ? "Sending…" : "Forgot password?") {
                            Task { await sendPasswordReset() }
                        }
                        .font(.dhCaption)
                        .foregroundStyle(Color.dogHouseBrown)
                        .disabled(isSendingReset || authService.isLoading)
                    }
                }
            }

            Button {
                Task { await submit() }
            } label: {
                Group {
                    if authService.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(mode == .logIn ? "Log In" : "Create Account")
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

            if showError {
                Text(errorText)
                    .font(.dhCaption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if let resetNotice {
                Text(resetNotice)
                    .font(.dhCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            SocialSignInButtons(onLightBackground: true)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .animation(.easeInOut(duration: 0.2), value: mode)
    }

    // MARK: - Validation

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespaces)
    }

    private var formIsValid: Bool {
        guard !trimmedEmail.isEmpty, trimmedEmail.contains("@"), password.count >= 6 else {
            return false
        }
        return mode == .logIn || password == confirmPassword
    }

    // MARK: - Actions

    private func submit() async {
        guard formIsValid, !authService.isLoading else { return }
        focusedField = nil
        showError = false
        do {
            switch mode {
            case .logIn:
                try await authService.signIn(email: trimmedEmail, password: password)
            case .signUp:
                // No name here on purpose — NameEntryView asks for the username
                // once the account exists, the same step Apple and Google hit.
                try await authService.signUp(
                    email: trimmedEmail,
                    password: password,
                    displayName: ""
                )
            }
            HapticService.shared.success()
        } catch {
            errorText = AuthService.friendlyError(error)
            showError = true
            HapticService.shared.error()
        }
    }

    private func sendPasswordReset() async {
        showError = false
        resetNotice = nil
        guard !trimmedEmail.isEmpty, trimmedEmail.contains("@") else {
            errorText = "Enter your email above and we'll send you a reset link."
            showError = true
            focusedField = .email
            return
        }
        focusedField = nil
        isSendingReset = true
        defer { isSendingReset = false }
        do {
            try await authService.sendPasswordReset(email: trimmedEmail)
            // Same wording whether or not the address has an account, so the
            // form can't be used to check which emails are registered.
            resetNotice = "If there's a DogHouse account for \(trimmedEmail), a reset link is on its way. Check your spam folder too."
            HapticService.shared.success()
        } catch {
            errorText = AuthService.friendlyError(error)
            showError = true
            HapticService.shared.error()
        }
    }
}

// MARK: - Triangle Shape

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    WelcomeView()
        .environmentObject(AuthService())
}
