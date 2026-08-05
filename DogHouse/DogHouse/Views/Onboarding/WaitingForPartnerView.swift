//
//  WaitingForPartnerView.swift
//  DogHouse
//
//  Step 2: Show your partner code, enter theirs, auto-advance when paired.
//  AuthService's real-time listener on the user doc detects partnerId changes,
//  which causes OnboardingContainerView to advance automatically.
//

import SwiftUI

struct WaitingForPartnerView: View {
    @EnvironmentObject var authService: AuthService

    @State private var partnerCode = ""
    @State private var showError = false
    @State private var errorText = ""
    @State private var isPairing = false
    @State private var pulsate = false

    private var myCode: String {
        authService.partnerCode ?? "------"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.cozyOrange)

                        Text("Connect With Your Partner")
                            .font(.dhTitle)

                        Text("Share your code or enter theirs to pair up")
                            .font(.dhBody)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)

                    // My code card
                    VStack(spacing: 12) {
                        Text("Your Code")
                            .font(.dhCaptionBold)
                            .foregroundStyle(.secondary)

                        Text(myCode)
                            .font(.dhTimer)
                            .tracking(6)
                            .foregroundStyle(Color.dogHouseBrown)
                            .scaleEffect(pulsate ? 1.03 : 1.0)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulsate)

                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.string = myCode
                                HapticService.shared.success()
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.dhCaptionBold)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                            }

                            ShareLink(item: "Join me on DogHouse! Enter my partner code: \(myCode)") {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.dhCaptionBold)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)

                    // OR divider
                    HStack {
                        Rectangle().fill(Color(.systemGray4)).frame(height: 1)
                        Text("OR")
                            .font(.dhCaptionBold)
                            .foregroundStyle(.secondary)
                        Rectangle().fill(Color(.systemGray4)).frame(height: 1)
                    }
                    .padding(.horizontal, 40)

                    // Enter partner's code
                    VStack(spacing: 12) {
                        Text("Enter Partner's Code")
                            .font(.dhCaptionBold)
                            .foregroundStyle(.secondary)

                        TextField("ABC123", text: $partnerCode)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onChange(of: partnerCode) { _, newValue in
                                if newValue.count > 6 {
                                    partnerCode = String(newValue.prefix(6))
                                }
                            }

                        Button {
                            Task { await pair() }
                        } label: {
                            Group {
                                if isPairing {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Connect")
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(partnerCode.count == 6 ? Color.cozyOrange : Color.gray.opacity(0.4))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(partnerCode.count != 6 || isPairing)

                        if showError {
                            Text(errorText)
                                .font(.dhCaption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Waiting indicator
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(Color.cozyOrange)
                        Text("Waiting for your partner to join...")
                            .font(.dhCaption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Pair Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") {
                        authService.signOut()
                    }
                    .font(.dhCaption)
                }
            }
            .onAppear { pulsate = true }
        }
    }

    private func pair() async {
        isPairing = true
        showError = false
        do {
            try await authService.pairWithPartner(code: partnerCode)
            HapticService.shared.success()
            // AuthService snapshot listener will update partnerId
            // → OnboardingContainerView auto-advances
        } catch {
            errorText = AuthService.friendlyError(error)
            showError = true
            HapticService.shared.error()
        }
        isPairing = false
    }
}

#Preview {
    WaitingForPartnerView()
        .environmentObject(AuthService())
}
