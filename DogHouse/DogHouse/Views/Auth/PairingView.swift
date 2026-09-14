//
//  PairingView.swift
//  DogHouse
//

import SwiftUI

struct PairingView: View {
    @EnvironmentObject var authService: AuthService

    @State private var partnerCode = ""
    @State private var showError = false
    @State private var errorText = ""
    @State private var pairingSucceeded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(Color.cozyOrange)
                        Text("Pair Up")
                            .font(.dhScreenTitle)
                        Text("Share your code with your partner, or enter theirs.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 20)

                    // Your code section
                    VStack(spacing: 12) {
                        Text("Your Code")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text(authService.partnerCode ?? "------")
                            .font(.dhTimer)
                            .tracking(6)

                        HStack(spacing: 16) {
                            Button {
                                if let code = authService.partnerCode {
                                    UIPasteboard.general.string = code
                                }
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.dogHouseBrown)

                            if let code = authService.partnerCode {
                                ShareLink(item: Legal.pairingLink(code: code), message: Text("Join me on DogHouse! Tap the link to pair, or enter my code: \(code)")) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                        .font(.subheadline.bold())
                                }
                                .buttonStyle(.bordered)
                                .tint(Color.dogHouseBrown)
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)

                    // Divider
                    HStack {
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(height: 1)
                        Text("OR")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 40)

                    // Enter partner code section
                    VStack(spacing: 16) {
                        Text("Enter Partner's Code")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        TextField("XXXXXX", text: $partnerCode)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .frame(maxWidth: 200)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            Task { await pair() }
                        } label: {
                            Group {
                                if authService.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Pair Up 💕")
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                partnerCode.count == 6
                                ? Color.cozyOrange
                                : Color.gray.opacity(0.4)
                            )
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(partnerCode.count != 6 || authService.isLoading)
                        .padding(.horizontal, 24)

                        if showError {
                            Text(errorText)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    Spacer(minLength: 32)
                }
            }
            .navigationTitle("Pair Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") {
                        authService.signOut()
                    }
                    .font(.subheadline)
                }
            }
            .onChange(of: authService.pendingPairCode, initial: true) { _, code in
                guard let code else { return }
                partnerCode = code
                authService.pendingPairCode = nil
            }
        }
    }

    // MARK: - Actions

    private func pair() async {
        showError = false
        do {
            try await authService.pairWithPartner(code: partnerCode)
            pairingSucceeded = true
        } catch {
            errorText = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    PairingView()
        .environmentObject(AuthService())
}
