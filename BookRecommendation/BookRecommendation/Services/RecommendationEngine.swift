//
//  RecommendationEngine.swift
//  
//
//  Created by Vira Fitriyani on 23/04/26.
//

import Combine
import Foundation

enum RecommendationMode {
    case popular
    case coldStart(Int)
    case personalized
    
    var description: String {
        switch self {
        case .popular:
            return "Popular Books"
        case .coldStart(let n):
            return "Based on \(n) rating\(n == 1 ? "" : "s")"
        case .personalized:
            return "Recommended For You"
        }
    }
}

class RecommendationEngine: ObservableObject {
    @Published var books:   [Book]               = []
    @Published var mode:    RecommendationMode   = .popular
    @Published var isLoading: Bool               = false
    
    private let svd:          SVDEngine
    private let popularBooks: [Book]
    private let booksMeta:    [String: Book]
    
    init() {
        // Load SVD engine
        guard let engine = SVDEngine.load() else {
            fatalError("Failed to load SVD model")
        }
        self.svd = engine
        
        // Load book metadata
        let meta = Self.loadBooksMeta()
        
        // Load popular books
        let popular = Self.loadPopularBooks(
            meta: meta)
        
        self.booksMeta = meta
        self.popularBooks = popular
        
        // Check a sample ISBN
        if let firstISBN = engine.itemMap.keys.first { }
    }
    
    // Called on login, after rating a book, on pull-to-refresh
    func refresh(session: UserSessionModel) {
        isLoading = true
        
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            let result = self.compute(session: session)

            self.books     = result.books
            self.mode      = result.mode
            self.isLoading = false
        }
    }
    
    // Core recommendation logic
    private func compute(session: UserSessionModel) -> (books: [Book], mode: RecommendationMode) {
        
        let rated    = session.sessionRatings
        let excluded = Set(rated.keys)
        
        // Case 1: Known user from dataset
        if !session.isNewUser && svd.userExists(session.userId) {
            print("Known user: \(session.userId)")
            let recs = svd.recommend(
                userId:       session.userId,
                excludeISBNs: excluded,
                n: 20
            )
            print("📊 Raw recs from SVD: \(recs.count)")
            print("📊 Sample rec: \(recs.first?.isbn ?? "none")")
            
            let books = enrich(recs)
            print("📖 Enriched books: \(books.count)")
            return (books, .personalized)
        }
        
        // Case 2: New user with at least 1 rating
        // Use fold-in approximation that improves with each rating
        if !rated.isEmpty {
            let recs = svd.approximateAndRecommend(
                ratedBooks:   rated,
                excludeISBNs: excluded,
                n: 20
            )
            let books = enrich(recs)
            return (books, .coldStart(rated.count))
        }
        
        // Case 3: New user without rating, show popular books
        let filtered = popularBooks.filter {
            !excluded.contains($0.isbn)
        }
        return (Array(filtered.prefix(20)), .popular)
    }
    
    // Enrich ISBN+score pairs with metadata
    private func enrich(
        _ recs: [(isbn: String, score: Float)]
    ) -> [Book] {
        recs.compactMap { rec -> Book? in
            guard var book = booksMeta[rec.isbn] else { return nil }
            book.score = Double(rec.score)
            return book
        }
    }
    
    // Loaders
    private static func loadBooksMeta() -> [String: Book] {
        
        guard let url = Bundle.main.url(
            forResource: "books_metadata",
            withExtension: "json"
        ) else {
            Bundle.main.paths(forResourcesOfType: "json", inDirectory: nil)
            return [:]
        }
        
        do {
            // Load data
            let data = try Data(contentsOf: url)
            
            // Decode JSON
            let decoder = JSONDecoder()
            let list = try decoder.decode([Book].self, from: data)
            
            // Convert to dictionary (ISBN → Book)
            let dict = Dictionary(uniqueKeysWithValues: list.map { ($0.isbn, $0) })
            
            return dict
            
        } catch {
            
            // print raw preview for debugging
            if let data = try? Data(contentsOf: url),
               let preview = String(data: data.prefix(200), encoding: .utf8) {
                print("📄 JSON preview:", preview)
            }
            
            return [:]
        }
    }
    
    private static func loadPopularBooks(
        meta: [String: Book]
    ) -> [Book] {
        
        struct PopularItem: Codable {
            let isbn:  String
            let score: Double
        }
        
        guard let url  = Bundle.main.url(
            forResource: "popular_books",
            withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode(
                [PopularItem].self, from: data)
        else { return [] }
        
        return list.compactMap { item -> Book? in
            guard var book = meta[item.isbn] else { return nil }
            book.score = item.score
            return book
        }
    }
}
