//
//  Logger+DogHouse.swift
//  DogHouse
//
//  Structured logging. `print` writes to the device console in release
//  builds and cannot be filtered, redacted, or captured off-device;
//  os.Logger gives level control and privacy-aware interpolation.
//
//  Convention: log the *shape* of a failure, never the payload. Firestore
//  documents carry display names, reasons and push tokens — interpolating
//  them into a log makes them readable by anyone with the device attached.
//

import Foundation
import OSLog

extension Logger {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.Harrison.DogHouse"

    /// Firestore decode failures, listener errors, and other data-layer faults
    static let data = Logger(subsystem: subsystem, category: "data")
    /// Push registration and notification routing
    static let push = Logger(subsystem: subsystem, category: "push")
}
