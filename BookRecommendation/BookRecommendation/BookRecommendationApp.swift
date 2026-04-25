//
//  BookRecommendationApp.swift
//  BookRecommendation
//
//  Created by Vira Fitriyani on 23/04/26.
//

import SwiftUI

@main
struct BookRecommendationApp: App {
    @StateObject private var session = UserSessionModel()
    @StateObject private var engine = RecommendationEngine()
    
    var body: some Scene {
        WindowGroup {
            if session.isLoggedIn {
                TabView {
                    HomeView()
                        .tabItem { Label("For You", systemImage: "house.fill")}
                    
                    ProfileView()
                        .tabItem { Label("Profile", systemImage: "person.fill")}
                }
                .environmentObject(session)
                .environmentObject(engine)
                
            } else {
                LoginView()
                    .environmentObject(session)
                    .onAppear { engine.reset() }
            }
        }
        // When user logout, clear the engine
        .onChange(of: session.isLoggedIn) {
            isLoggedIn in if !isLoggedIn { engine.reset() }
        }
    }
}
