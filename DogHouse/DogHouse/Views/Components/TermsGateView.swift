//
//  TermsGateView.swift
//  DogHouse
//
//  One-time acceptance of the Terms of Use for accounts that predate them
//  (new accounts accept on the username screen). Presented as a sheet that
//  cannot be swiped away: nothing user-generated may be posted until the
//  current terms version is on the profile.
//

import SwiftUI

struct TermsGateView: View {
    @EnvironmentObject var authService: AuthService
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 24) {
            Text("🐕").font(.system(size: 56))
            Text("A quick house rule")
                .font(.dhTitle)
            Text("DogHouse is a place for couples and their friends to tease each other kindly. Anything hateful, sexual, or that shares someone's private life gets removed, and repeat offenders lose their account. You can report or block anyone from the feed.")
                .font(.dhBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            LegalLinksText()

            Button {
                Task { await accept() }
            } label: {
                Group {
                    if isSaving { ProgressView().tint(.white) } else { Text("I agree") }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.cozyOrange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isSaving)

            if let errorText {
                Text(errorText).font(.dhCaption).foregroundStyle(.red)
            }
        }
        .padding(28)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }

    private func accept() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await authService.acceptTerms()
            HapticService.shared.success()
        } catch {
            errorText = AuthService.friendlyError(error)
        }
    }
}

/// "By continuing you agree to the Terms of Use and Privacy Policy" with
/// both as tappable links. Shared by the username screen and the gate.
struct LegalLinksText: View {
    var body: some View {
        Text("By continuing you agree to the [Terms of Use](\(Legal.termsURL.absoluteString)) and [Privacy Policy](\(Legal.privacyURL.absoluteString)).")
            .font(.dhCaption)
            .foregroundStyle(.secondary)
            .tint(Color.dogHouseBrown)
            .multilineTextAlignment(.center)
    }
}
