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
    
    var body: some Scene {
        WindowGroup {
            if session.isLoggedIn {
                HomeView()
                    .environmentObject(session)
            } else {
                LoginView()
                    .environmentObject(session)
            }
        }
    }
}
