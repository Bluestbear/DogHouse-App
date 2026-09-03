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
                VStack(spacing: 8) {
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
        Text("Welcome to DogHouse!")
            .font(.dhDisplay)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.top, 56)
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
        // The mascot peeks over the top edge, nosy about what's being typed.
        // Drawn as the card's background so the card hides its lower half.
        .background(alignment: .top) {
            // The real avatar, big, with its body behind the card: only the
            // head and ears show above the edge. The tail is switched off
            // rather than clipped — it overlaps the head and the ears in
            // both axes, so any mask that hid it would clip them too.
            AvatarView(
                avatar: DogAvatar.avatar(for: "dog_1"),
                mood: .happy,
                size: 270,
                showsTail: false,
                gaze: focusedField != nil ? 3 : 0
            )
            .rotationEffect(.degrees(-4))
            .offset(y: -165)
            .accessibilityHidden(true)
        }
        .overlay(alignment: .top) {
            PeekingPaws()
                .offset(y: -12)
        }
        .padding(.top, 150)
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

// MARK: - Peeking Paws

/// The avatar's paws, hooked over the card's edge, drawn the way AvatarView
/// draws them (a 14×9 rounded rect at the avatar's scale) so they match the
/// head above.
struct PeekingPaws: View {
    private let fur = DogAvatar.avatar(for: "dog_1").primaryColor
    private let scale: CGFloat = 270 / 80

    var body: some View {
        HStack(spacing: 13 * scale) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 5 * scale)
                    .fill(fur)
                    .frame(width: 14 * scale, height: 9 * scale)
            }
        }
        .accessibilityHidden(true)
    }
}

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
