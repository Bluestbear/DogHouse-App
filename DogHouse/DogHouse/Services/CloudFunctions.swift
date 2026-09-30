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
//  Transient failures are retried with exponential backoff. Retrying a
//  spend is only safe because each attempt carries the same idempotency
//  key: the server records the key and replays the stored result instead of
//  charging twice. Never reuse a key across two *different* user intents.
//

import Foundation
import OSLog
// @preconcurrency: callable payloads are [String: Any] by API design and
// cannot be Sendable. The dictionary is built locally and never mutated
// after the call, so there is nothing to race on.
@preconcurrency import FirebaseFunctions

final class CloudFunctions {
    static let shared = CloudFunctions()

    // Functions are deployed in europe-west1; the client must target the
    // same region or calls 404.
    private let functions = Functions.functions(region: "europe-west1")
    private let log = Logger(subsystem: Logger.subsystem, category: "functions")

    /// Attempts per call, including the first.
    private let maxAttempts = 3
    /// First backoff step; doubles each retry (0.5s, 1s) plus jitter.
    private let baseDelay: Duration = .milliseconds(500)

    private init() {}

    /// Call a callable and decode its result dictionary. Throws a
    /// user-friendly message on FunctionsError (the server sets these).
    ///
    /// - Parameter idempotencyKey: Supplied automatically. The same key is
    ///   reused across retries of one logical action, so a call that
    ///   actually succeeded but whose response was lost cannot be applied
    ///   twice.
    @discardableResult
    func call(
        _ name: String,
        _ data: [String: Any] = [:],
        idempotencyKey: String = UUID().uuidString
    ) async throws -> [String: Any] {
        var payload = data
        payload["idempotencyKey"] = idempotencyKey

        var attempt = 1
        while true {
            do {
                let result = try await functions.httpsCallable(name).call(payload)
                return result.data as? [String: Any] ?? [:]
            } catch {
                let nsError = error as NSError
                guard attempt < maxAttempts, Self.isRetryable(nsError) else {
                    throw Self.userFacingError(nsError)
                }
                // Exponential backoff with jitter, so two phones retrying the
                // same outage don't march in lockstep.
                let step = baseDelay * Int(pow(2.0, Double(attempt - 1)))
                let jitter = Duration.milliseconds(Int.random(in: 0...200))
                log.info("Retrying \(name, privacy: .public) (attempt \(attempt + 1))")
                try? await Task.sleep(for: step + jitter)
                attempt += 1
            }
        }
    }

    // MARK: - Error Classification

    /// Only errors that leave the server state unchanged, or that the
    /// idempotency key makes safe to repeat, are retried. Business
    /// rejections (no grace left, not enough treats, no partner) are final
    /// and must surface immediately.
    private static func isRetryable(_ error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain {
            return [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost,
                    NSURLErrorNotConnectedToInternet, NSURLErrorCannotConnectToHost]
                .contains(error.code)
        }
        guard error.domain == FunctionsErrorDomain,
              let code = FunctionsErrorCode(rawValue: error.code) else { return false }
        switch code {
        case .unavailable, .deadlineExceeded, .internal, .aborted:
            return true
        default:
            return false
        }
    }

    private static func userFacingError(_ error: NSError) -> NSError {
        // Firebase surfaces thrown HttpsError.message in localizedDescription.
        let message: String
        if error.domain == NSURLErrorDomain {
            message = "No connection. Check your network and try again."
        } else {
            message = error.localizedDescription
        }
        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
        // Keep the server's structured details (e.g. {reason: "daily-game-limit"})
        // so callers can tell apart errors that share a code.
        if let details = error.userInfo[FunctionsErrorDetailsKey] {
            userInfo[FunctionsErrorDetailsKey] = details
        }
        return NSError(domain: "CloudFunctions", code: error.code, userInfo: userInfo)
    }
}
