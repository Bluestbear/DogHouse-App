//
//  CloudFunctions.swift
//  DogHouse
//
//  Thin wrapper around the callable Cloud Functions. All economy-affecting
//  actions (send to doghouse, release, purchases, treat awards) run through
//  these so the server — not the client — is the source of truth. The
//  protected user fields (treats, graceCharges, immunityUntil, wishCards,
//  ownedItemIds) are read-only to clients via security rules.
//

import Foundation
import FirebaseFunctions

final class CloudFunctions {
    static let shared = CloudFunctions()

    // Functions are deployed in europe-west1; the client must target the
    // same region or calls 404.
    private let functions = Functions.functions(region: "europe-west1")

    private init() {}

    /// Call a callable and decode its result dictionary. Throws a
    /// user-friendly message on FunctionsError (the server sets these).
    @discardableResult
    func call(_ name: String, _ data: [String: Any] = [:]) async throws -> [String: Any] {
        do {
            let result = try await functions.httpsCallable(name).call(data)
            return result.data as? [String: Any] ?? [:]
        } catch {
            // Firebase surfaces thrown HttpsError.message here
            throw NSError(
                domain: "CloudFunctions",
                code: (error as NSError).code,
                userInfo: [NSLocalizedDescriptionKey: (error as NSError).localizedDescription]
            )
        }
    }
}
