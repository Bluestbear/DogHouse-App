//
//  PrivacyDisclosure.swift
//  DogHouse
//
//  The privacy policy and the switch that acts on it, folded into one row of
//  Profile. Someone deciding whether to share usage data should find that
//  choice next to the policy that explains what the data is, rather than as a
//  loose toggle several rows away from it.
//
//  The policy itself lives on the web (Legal.privacyURL) and opens in Safari:
//  one copy of the text, in one place, with nothing in the app to drift out of
//  sync with it.
//

import SwiftUI

struct PrivacyDisclosure: View {
    @State private var isExpanded = false
    @State private var analyticsEnabled = AnalyticsService.shared.isEnabled

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Link(destination: Legal.privacyURL) {
                Label("Open in Safari", systemImage: "safari")
            }

            Toggle(isOn: $analyticsEnabled) {
                Label("Share Usage Data", systemImage: "chart.bar.fill")
            }
            .onChange(of: analyticsEnabled) { _, newValue in
                AnalyticsService.shared.isEnabled = newValue
            }
        } label: {
            Label("Privacy Policy", systemImage: "lock.shield.fill")
        }
    }
}

#Preview {
    List {
        Section {
            PrivacyDisclosure()
        }
    }
}
