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
        VStack(spacing: 10) {
            Text("DogHouse")
                .font(.dhDisplay)
                .foregroundStyle(.white)

            Text("Messed up? You're in the DogHouse.")
                .font(.dhBody)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
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
            PeekingDogHead(lookingDown: focusedField != nil)
                .offset(y: -122)
        }
        .overlay(alignment: .top) {
            PeekingPaws()
                .offset(y: -8)
        }
        .padding(.top, 118)
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

// MARK: - Peeking Mascot

/// The Golden dog's face, drawn the way the app icon draws it, resting its
/// chin on the top edge of the sign-in card.
struct PeekingDogHead: View {
    var lookingDown: Bool

    private let fur = Color(red: 0.82, green: 0.63, blue: 0.25)
    private let furDark = Color(red: 0.68, green: 0.50, blue: 0.16)
    private let muzzle = Color(red: 0.95, green: 0.84, blue: 0.60)
    private let dark = Color(red: 0.12, green: 0.08, blue: 0.08)

    @State private var isBlinking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Ears
            Ellipse().fill(furDark).frame(width: 46, height: 60)
                .rotationEffect(.degrees(-18)).offset(x: -64, y: -36)
            Ellipse().fill(furDark).frame(width: 46, height: 60)
                .rotationEffect(.degrees(18)).offset(x: 64, y: -36)

            Circle().fill(fur).frame(width: 156, height: 156)

            Ellipse().fill(muzzle).frame(width: 96, height: 70).offset(y: 36)

            ForEach([-31, 31], id: \.self) { x in
                ZStack {
                    Circle().fill(.white).frame(width: 42, height: 42)
                    Circle().fill(dark).frame(width: 24, height: 24)
                        .offset(y: lookingDown ? 7 : 1)
                    Circle().fill(.white).frame(width: 9, height: 9)
                        .offset(x: 6, y: lookingDown ? 1 : -6)
                }
                .scaleEffect(y: isBlinking ? 0.08 : 1, anchor: .center)
                .offset(x: CGFloat(x), y: -6)
                .animation(.easeInOut(duration: 0.25), value: lookingDown)
            }

            Ellipse().fill(dark).frame(width: 32, height: 22).offset(y: 22)
            Ellipse().fill(Color(red: 0.29, green: 0.21, blue: 0.21)).frame(width: 9, height: 5).offset(x: -6, y: 17)

            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addQuadCurve(to: CGPoint(x: 40, y: 0), control: CGPoint(x: 20, y: 22))
            }
            .stroke(dark, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            .frame(width: 40, height: 14)
            .offset(y: 46)
        }
        .frame(width: 200, height: 170)
        .rotationEffect(.degrees(-5))
        .accessibilityHidden(true)
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.5...5.5)))
                withAnimation(.easeIn(duration: 0.07)) { isBlinking = true }
                try? await Task.sleep(for: .seconds(0.1))
                withAnimation(.easeOut(duration: 0.11)) { isBlinking = false }
            }
        }
    }
}

/// Two paws hooked over the card's edge, so the dog is clearly hanging on
/// to look, not floating behind it.
struct PeekingPaws: View {
    private let fur = Color(red: 0.82, green: 0.63, blue: 0.25)
    private let line = Color(red: 0.62, green: 0.45, blue: 0.16)

    var body: some View {
        HStack(spacing: 58) {
            ForEach(0..<2, id: \.self) { _ in
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(fur).frame(width: 36, height: 22)
                    HStack(spacing: 7) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule().fill(line.opacity(0.6)).frame(width: 2, height: 9)
                        }
                    }
                    .offset(y: 3)
                }
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
