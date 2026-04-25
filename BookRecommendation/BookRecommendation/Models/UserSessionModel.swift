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
    
    private let activeUserIdKey = "activeUserId"
    
    init() {
        // Restore previous session if exists
        if let saved = UserDefaults.standard.string(forKey: activeUserIdKey) {
            userId = saved
            isLoggedIn = true
            isNewUser = false
            loadRatings(for: saved)
        }
    }
    
    func login(mode: LoginMode) {
        switch mode {
        case .existingUser(let id):
            userId = id
            isNewUser = false
        case .newUser:
            // Generate unique ID for new user, 6 digit numeric ID same format as the SVD dataset
            let id = String(Int.random(in: 100_000...999_999))
            userId = id
            isNewUser = true
        }
        isLoggedIn = true
        UserDefaults.standard.set(userId, forKey: activeUserIdKey)
        loadRatings(for: userId)
    }
    
    func logout() {
        saveRatings(for: userId)
        UserDefaults.standard.removeObject(forKey: activeUserIdKey)
        isLoggedIn = false
        isNewUser = false
        sessionRatings = [:]
        userId = ""
    }
    
    func rateBook(isbn: String, rating: Float) {
        sessionRatings[isbn] = rating
        saveRatings(for: userId)
        print("🔍 Rated ISBN: '\(isbn)'")
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
    
    private func ratingsKey(for id: String) -> String {
        "userRatings_\(id)"
    }
    
    private func saveRatings(for id: String) {
        guard !id.isEmpty else { return }
        if let data = try? JSONEncoder().encode(sessionRatings) {
            UserDefaults.standard.set(data, forKey: ratingsKey(for: id))
        }
    }
    
    private func loadRatings(for id: String) {
        guard !id.isEmpty,
              let data  = UserDefaults.standard.data(forKey: ratingsKey(for: id)),
              let saved = try? JSONDecoder().decode([String: Float].self, from: data)
        else {
            sessionRatings = [:]
            return
        }
        sessionRatings = saved
    }
}
