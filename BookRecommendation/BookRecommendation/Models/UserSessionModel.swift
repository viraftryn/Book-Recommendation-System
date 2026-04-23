//
//  UserSessionModel.swift
//  
//
//  Created by Vira Fitriyani on 22/04/26.
//

import Combine
import Foundation

enum LoginMode {
    case existingUser(String)
    case newUser
}

class UserSessionModel: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var userId: String = ""
    @Published var isNewUser: Bool = false
    
    // Ratings that this user has given during session
    @Published var sessionRatings: [String: Float] = [:]
    
    private let ratingsKey = "userRatings"
    private let userIdKey = "userId"
    
    init() {
        // Restore previous session if exists
        if let saved = UserDefaults.standard.string(forKey: userIdKey) {
            userId = saved
            isLoggedIn = true
        }
        loadRatings()
    }
    
    func login(mode: LoginMode) {
        switch mode {
        case .existingUser(let id):
            userId = id
            isNewUser = false
        case .newUser:
            // Generate unique ID for new user
            userId = "user_\(UUID().uuidString.prefix(8))"
            isNewUser = true
        }
        isLoggedIn = true
        UserDefaults.standard.set(userId, forKey: userIdKey)
    }
    
    func logout() {
        isLoggedIn = false
        userId = ""
        isNewUser = false
        sessionRatings = [:]
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: ratingsKey)
    }
    
    func rateBook(isbn: String, rating: Float) {
        sessionRatings[isbn] = rating
        saveRatings()
    }
    
    func hasRated(isbn: String) -> Bool {
        return sessionRatings[isbn] != nil
    }
    
    var ratingCount: Int {
        sessionRatings.count
    }
    
    // ratings clipped >= 5
    var modelRatings: [String: Float] {
        sessionRatings.mapValues { max($0, 5.0)}
    }
    
    private func saveRatings() {
        if let data = try? JSONEncoder().encode(sessionRatings) {
            UserDefaults.standard.set(data, forKey: ratingsKey)
        }
    }
    
    private func loadRatings() {
        guard let data = UserDefaults.standard.data(forKey: ratingsKey),
              let saved = try? JSONDecoder().decode([String: Float].self, from: data) else { return }
        sessionRatings = saved
    }
}
