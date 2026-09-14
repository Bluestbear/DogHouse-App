//
//  Legal.swift
//  DogHouse
//
//  Public URLs and the terms version users must accept before they can
//  post content other people see (App Store Guideline 1.2).
//

import Foundation

enum Legal {
    static let siteURL = URL(string: "https://doghouse-5e80e.web.app")!
    static let privacyURL = siteURL.appending(path: "privacy.html")
    static let termsURL = siteURL.appending(path: "terms.html")
    static let supportEmail = "harrisonkennykrampe@gmail.com"

    /// Bump when the terms change materially; every account must accept
    /// the current version once (TermsGateView) before using the app.
    static let termsVersion = "2026-09"

    /// Universal link that pre-fills a partner code on the pairing screen.
    static func pairingLink(code: String) -> URL {
        siteURL.appending(path: "pair").appending(path: code)
    }

    /// The code carried by a pairing link, if `url` is one. Accepts both the
    /// universal link (https://…/pair/CODE) and the custom scheme fallback
    /// (doghouse://pair/CODE) the web page uses to reopen an installed app.
    static func pairingCode(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let isScheme = url.scheme == "doghouse" && url.host == "pair"
        let isUniversal = url.host == siteURL.host && parts.first == "pair"
        guard isScheme || isUniversal else { return nil }
        let raw = (isScheme ? parts.first : parts.dropFirst().first) ?? ""
        let code = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        return code.count == 6 ? code : nil
    }
}
