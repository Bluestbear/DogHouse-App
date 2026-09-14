//
//  TimeInterval+Formatting.swift
//  DogHouse
//

import Foundation

extension TimeInterval {
    /// Formats as "Xh Ym Zs" for display in timers, rolling over to
    /// "Xd Yh Zm Ws" after a day — "9d 4h" means something, "220h" does not.
    var formattedTimer: String {
        let totalSeconds = Int(self)
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m \(seconds)s"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    /// Formats as a short duration string like "2 days", "5 hours"
    var formattedDuration: String {
        let totalSeconds = Int(self)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60

        if days > 0 {
            return days == 1 ? "1 day" : "\(days) days"
        } else if hours > 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        } else if minutes > 0 {
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        } else {
            return "just now"
        }
    }
}
