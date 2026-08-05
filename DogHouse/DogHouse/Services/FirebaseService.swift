//
//  FirebaseService.swift
//  DogHouse
//
//  Firestore wrapper providing typed collection references,
//  a pre-configured encoder/decoder, and shared helpers.
//

import Foundation
import FirebaseFirestore

final class FirebaseService {
    static let shared = FirebaseService()

    let db: Firestore
    let encoder: Firestore.Encoder
    let decoder: Firestore.Decoder

    private init() {
        self.db = Firestore.firestore()

        let enc = Firestore.Encoder()
        enc.dateEncodingStrategy = .timestamp
        self.encoder = enc

        let dec = Firestore.Decoder()
        dec.dateDecodingStrategy = .timestamp
        self.decoder = dec
    }

    // MARK: - Collection References

    var usersCollection: CollectionReference { db.collection("users") }
    var partnerCodesCollection: CollectionReference { db.collection("partnerCodes") }
    var doghouseEventsCollection: CollectionReference { db.collection("doghouseEvents") }
    var voteEventsCollection: CollectionReference { db.collection("voteEvents") }
    var onboardingTasksCollection: CollectionReference { db.collection("onboardingTasks") }
    var coupleTasksCollection: CollectionReference { db.collection("coupleTasks") }
    var bellyRubsCollection: CollectionReference { db.collection("bellyRubs") }
    var feedPostsCollection: CollectionReference { db.collection("feedPosts") }
    var challengesCollection: CollectionReference { db.collection("challenges") }
    var coupleMetaCollection: CollectionReference { db.collection("coupleMeta") }
    var wishesCollection: CollectionReference { db.collection("wishes") }

    // MARK: - Helpers

    /// Owner-only companion document holding this account's secrets
    /// (pairing code, push token). See the /users/{uid}/private rules.
    func privateDataDocument(for userId: String) -> DocumentReference {
        usersCollection.document(userId).collection("private").document("data")
    }

    /// Build a coupleKey from two user IDs (sorted, underscore-joined)
    func coupleKey(userId1: String, userId2: String) -> String {
        [userId1, userId2].sorted().joined(separator: "_")
    }

    // MARK: - Generic Decode

    /// Decode a Firestore document into a Codable model, injecting the document ID as the `id` field
    func decode<T: Decodable>(_ type: T.Type, from document: DocumentSnapshot) throws -> T {
        guard let data = document.data() else {
            throw NSError(domain: "FirebaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Document data was empty"])
        }
        var mutableData = data
        mutableData["id"] = document.documentID
        return try decoder.decode(type, from: mutableData)
    }
}
