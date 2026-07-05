//
//  WelcomeView.swift
//  DogHouse
//

import SwiftUI

struct WelcomeView: View {
    @State private var showSignUp = false
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.cozyOrange.opacity(0.8), Color.dogHouseBrown],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // Dog house illustration
                    VStack(spacing: 8) {
                        ZStack {
                            // Roof
                            Triangle()
                                .fill(Color.dogHouseBrown)
                                .frame(width: 160, height: 80)
                                .offset(y: -20)

                            // House body
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.dogHouseBrown.opacity(0.8))
                                .frame(width: 130, height: 100)
                                .offset(y: 30)

                            // Door
                            UnevenRoundedRectangle(
                                topLeadingRadius: 25,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 25
                            )
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 50, height: 60)
                            .offset(y: 50)
                        }
                        .frame(height: 180)
                    }

                    // Title
                    VStack(spacing: 8) {
                        Text("DogHouse")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Messed up? You're in the DogHouse. 🐕")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    Spacer()

                    // Buttons
                    VStack(spacing: 14) {
                        NavigationLink(destination: SignUpView()) {
                            Text("Sign Up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.white)
                                .foregroundStyle(Color.dogHouseBrown)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        NavigationLink(destination: LoginView()) {
                            Text("Log In")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.white.opacity(0.2))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(.white.opacity(0.5), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
                }
            }
        }
    }
}

// MARK: - Triangle Shape

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    WelcomeView()
}
