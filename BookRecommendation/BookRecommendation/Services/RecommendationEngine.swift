//
//  RecommendationEngine.swift
//
//
//  Created by Vira Fitriyani on 23/04/26.
//

import Combine
import Foundation
import SwiftUI

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
    @Published var animationTrigger = UUID()
    
    private let svd:          SVDEngine
    private let popularBooks: [Book]
    let booksMeta:    [String: Book]
    
    private var seenISBNs: Set<String> = []
    
    //    private var popularRotationOffset = 0 // for tracking where we are in the popular list for rotation on pull-to-refresh
    
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
        
        let modelISBNs = Set(engine.itemMap.keys)
        let metadataISBNs = Set(meta.keys)
        let overlap = modelISBNs.intersection(metadataISBNs)
        print("📚 ISBN overlap: \(overlap.count) / \(modelISBNs.count) model items found in metadata (\(metadataISBNs.count) metadata total)")
        if overlap.isEmpty {
            print("⚠️  Zero overlap — check that books_metadata.json ISBNs match svd_model_export.json item_map keys")
        }
    }
    
    // Called on logout
    func reset() {
        books     = []
        mode      = .popular
        seenISBNs = []
    }
    
    // Called on login, after rating a book, on pull-to-refresh
    func refresh(session: UserSessionModel, isUserInitiated: Bool = false) {
        isLoading = true
        
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            let result = self.compute(session: session, isUserInitiated: isUserInitiated)
            
            await MainActor.run {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    self.books     = result.books
                    self.mode      = result.mode
                    self.isLoading = false
                }
                
                self.animationTrigger = UUID()
                // Track what the user has now seen
                result.books.forEach { self.seenISBNs.insert($0.isbn) }
            }
        }
    }
    
    // Load more popular books
    func exploreMore(session: UserSessionModel) {
        let shown = Set(books.map(\.isbn))
        let excluded = shown
            .union(seenISBNs)
            .union(Set(session.sessionRatings.keys))
        var more: [Book] = []
        
        switch mode {
        case .personalized where svd.userExists(session.userId):
            // Pull the next batch from a deeper SVD query
            let recs = svd.recommend(
                userId:       session.userId,
                excludeISBNs: excluded,
                n:10
            )
            more = enrich(recs)
            
        case .coldStart where !session.sessionRatings.isEmpty:
            let recs = svd.approximateAndRecommend(
                ratedBooks: session.modelRatings,
                excludeISBNs: excluded,
                n:10
            )
            more = enrich(recs)
            
        default:
            break
        }
        
        // Supplement with popular books if SVD pool came up short (or for popular mode)
        if more.count < 10 {
            let popMore = popularBooks
                .filter { !excluded.contains($0.isbn) && !more.map(\.isbn).contains($0.isbn) }
                .prefix(10 - more.count)
            more += popMore
        }
        
        guard !more.isEmpty else { return }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            books.append(contentsOf: more)
        }
    }
    
    // Core recommendation logic
    private func compute(session: UserSessionModel, isUserInitiated: Bool) -> (books: [Book], mode: RecommendationMode) {
        
        let rated    = session.sessionRatings
        let excluded = Set(session.sessionRatings.keys)
        
        // Clip rate 1-4
        //        let modelRatings = session.modelRatings
        
        // On pull-to-refresh, also exclude everything already seen so the
        // list genuinely changes rather than reshuffling the same books.
        let refreshExcluded = isUserInitiated
        ? excluded.union(seenISBNs)
        : excluded
        
        // Case 1: Known user from dataset
        if !session.isNewUser && svd.userExists(session.userId) {
            print("Known user: \(session.userId)")
            var recs = svd.recommend(
                userId:       session.userId,
                excludeISBNs: refreshExcluded,
                n: svd.itemsWithFactorData
            )
            print("   SVD returned \(recs.count) raw recs")
            
            if isUserInitiated {
                recs.shuffle()
            }
            
            var books = enrich(Array(recs.prefix(20)))
            print("   After enrich: \(books.count) books")
            
            if books.count < 10 {
                print("   ⚠️ SVD pool small (\(books.count)) — blending popular books")
                books = blendWithPopular(svdBooks: books,
                                         excluded: refreshExcluded,
                                         target: 20)
            }
            print("   Final: \(books.count) books")
            return (books, .personalized)
        }
        
        // Case 2: New user with at least 1 rating
        // Use fold-in approximation that improves with each rating
        if !rated.isEmpty {
            print("🌱 Case 2 — cold start with \(rated.count) ratings")
            
            var recs = svd.approximateAndRecommend(
                ratedBooks:   session.modelRatings,
                excludeISBNs: refreshExcluded,
                n: svd.itemsWithFactorData
            )
            print("   Fold-in pool: \(recs.count) items")
            
            if isUserInitiated { recs.shuffle() }
            
            var books = enrich(Array(recs.prefix(20)))
            
            if books.count < 10 {
                print("   ⚠️ Fold-in pool small (\(books.count)) — blending popular books")
                books = blendWithPopular(svdBooks: books,
                                         excluded: refreshExcluded,
                                         target: 20)
            }
            print("   Final: \(books.count) books")
            return (books, .coldStart(rated.count))
        }
        
        // Case 3: New user without rating, show popular books
        let filtered = popularBooks.filter { !refreshExcluded.contains($0.isbn) }
        return (Array(filtered.prefix(20)), .popular)
    }
    
    private func blendWithPopular(
        svdBooks: [Book],
        excluded: Set<String>,
        target:   Int
    ) -> [Book] {
        let svdISBNs = Set(svdBooks.map(\.isbn))
        let popFill  = popularBooks
            .filter { !excluded.contains($0.isbn) && !svdISBNs.contains($0.isbn) }
            .prefix(target - svdBooks.count)
        return svdBooks + popFill
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
        ),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Book].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.isbn, $0) })
    }
    
    private static func loadPopularBooks(
        meta: [String: Book]
    ) -> [Book] {
        
        struct P: Codable { let isbn: String; let score: Double }
        guard let url  = Bundle.main.url(forResource: "popular_books", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([P].self, from: data)
        else { return [] }
        return list.compactMap { item -> Book? in
            guard var book = meta[item.isbn] else { return nil }
            book.score = item.score
            return book
        }
    }
}
