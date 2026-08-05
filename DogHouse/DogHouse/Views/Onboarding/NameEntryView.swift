//
//  NameEntryView.swift
//  DogHouse
//
//  Step 1 (conditional): ask for a display name when the sign-in provider
//  didn't give us one.
//
//  Apple returns the user's name on the FIRST authorization only, and only if
//  they choose to share it — with "Hide My Email" there is nothing usable at
//  all. Email sign-up collects a name in the form, so this never appears for
//  those accounts. Without it, a partner would see a blank name everywhere.
//

import SwiftUI

struct NameEntryView: View {
    @EnvironmentObject var authService: AuthService

    @State private var name = ""
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorText = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.cozyOrange)

                        Text("What should we call you?")
                            .font(.dhTitle)
                            .multilineTextAlignment(.center)

                        Text("This is the name your partner sees.")
                            .font(.dhBody)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)

                    TextField("Your name", text: $name)
                        .font(.dhBody)
                        .textContentType(.givenName)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 24)

                    Button {
                        Task { await save() }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Continue")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(trimmedName.isEmpty ? Color.gray.opacity(0.4) : Color.cozyOrange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(trimmedName.isEmpty || isSaving)
                    .padding(.horizontal, 24)

                    if showError {
                        Text(errorText)
                            .font(.dhCaption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func save() async {
        showError = false
        isSaving = true
        defer { isSaving = false }
        do {
            try await authService.updateDisplayName(trimmedName)
            HapticService.shared.success()
            // The user-document listener picks the new name up and
            // OnboardingContainerView advances on its own.
        } catch {
            errorText = AuthService.friendlyError(error)
            showError = true
        }
    }
}

#Preview {
    NameEntryView()
        .environmentObject(AuthService())
}
