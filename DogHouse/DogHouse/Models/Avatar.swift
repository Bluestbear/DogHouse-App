//
//  Avatar.swift
//  DogHouse

import SwiftUI

enum AvatarMood: String {
    case happy
    case cozy
    case sad
    case hungry
    case freezing
    case dramatic
}

struct DogAvatar: Identifiable {
    let id: String
    let name: String
    let primaryColor: Color   // main fur
    let secondaryColor: Color // darker accent / spots
    let muzzleColor: Color    // lighter muzzle and chest patch

    static let allAvatars: [DogAvatar] = [
        DogAvatar(
            id: "dog_1", name: "Golden",
            primaryColor:   Color(red: 0.82, green: 0.63, blue: 0.25),
            secondaryColor: Color(red: 0.68, green: 0.50, blue: 0.16),
            muzzleColor:    Color(red: 0.95, green: 0.84, blue: 0.60)
        ),
        DogAvatar(
            id: "dog_2", name: "Husky",
            primaryColor:   Color(red: 0.72, green: 0.75, blue: 0.80),
            secondaryColor: Color(red: 0.30, green: 0.32, blue: 0.36),
            muzzleColor:    Color(red: 0.94, green: 0.94, blue: 0.96)
        ),
        DogAvatar(
            id: "dog_3", name: "Corgi",
            primaryColor:   Color(red: 0.90, green: 0.64, blue: 0.26),
            secondaryColor: Color(red: 0.72, green: 0.48, blue: 0.16),
            muzzleColor:    Color(red: 0.98, green: 0.93, blue: 0.84)
        ),
        DogAvatar(
            id: "dog_4", name: "Poodle",
            primaryColor:   Color(red: 0.80, green: 0.78, blue: 0.76),
            secondaryColor: Color(red: 0.58, green: 0.55, blue: 0.52),
            muzzleColor:    Color(red: 0.96, green: 0.95, blue: 0.94)
        ),
        DogAvatar(
            id: "dog_5", name: "Dalmatian",
            primaryColor:   Color(red: 0.97, green: 0.97, blue: 0.97),
            secondaryColor: Color(red: 0.18, green: 0.18, blue: 0.18),
            muzzleColor:    Color(red: 0.99, green: 0.97, blue: 0.94)
        ),
        DogAvatar(
            id: "dog_6", name: "Bulldog",
            primaryColor:   Color(red: 0.76, green: 0.61, blue: 0.46),
            secondaryColor: Color(red: 0.58, green: 0.44, blue: 0.30),
            muzzleColor:    Color(red: 0.94, green: 0.84, blue: 0.70)
        ),
        DogAvatar(
            id: "dog_7", name: "Shiba",
            primaryColor:   Color(red: 0.88, green: 0.55, blue: 0.20),
            secondaryColor: Color(red: 0.70, green: 0.40, blue: 0.12),
            muzzleColor:    Color(red: 0.98, green: 0.93, blue: 0.82)
        ),
        DogAvatar(
            id: "dog_8", name: "Beagle",
            primaryColor:   Color(red: 0.72, green: 0.50, blue: 0.26),
            secondaryColor: Color(red: 0.30, green: 0.18, blue: 0.08),
            muzzleColor:    Color(red: 0.96, green: 0.87, blue: 0.70)
        ),
    ]

    static func avatar(for id: String) -> DogAvatar {
        allAvatars.first { $0.id == id } ?? allAvatars[0]
    }
}
