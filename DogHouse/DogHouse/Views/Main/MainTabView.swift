//
//  MainTabView.swift
//  DogHouse
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeView()
                    .environmentObject(authService)
            }

            Tab("Friends", systemImage: "person.2.fill") {
                FriendsTabView()
                    .environmentObject(authService)
            }

            Tab("Shop", systemImage: "bag.fill") {
                ShopTabView()
                    .environmentObject(authService)
            }

            Tab("Profile", systemImage: "person.crop.circle.fill") {
                ProfileTabView()
                    .environmentObject(authService)
            }
        }
        .tint(Color.dogHouseBrown)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthService())
}
