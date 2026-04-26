//
//  SVDEngine.swift
//
//
//  Created by Vira Fitriyani on 22/04/26.
//

import Foundation
import Accelerate

class SVDEngine {
    let globalMean: Float
    let nFactors:   Int
    let nUsers:     Int
    let ratingMin:  Float
    let ratingMax:  Float

    private let userFactors: [Float]
    private let itemFactors: [Float]
    private let userBiases:  [Float]
    private let itemBiases:  [Float]

    let userMap: [String: Int]
    let itemMap: [String: Int]

    private let itemReverseMap: [Int: String]
    private let normalisedItemMap: [String: Int]

    let itemsWithFactorData: Int

    // Average L2 norm of trained user vectors.
    // Used to scale fold-in vectors to the same magnitude so that
    // dot products are on the same scale as those of trained users.
    private let avgUserNorm: Float

    // MARK: – Load
    static func load() -> SVDEngine? {
        guard let url  = Bundle.main.url(forResource: "svd_model_export", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return SVDEngine(json: json)
    }

    private init(json: [String: Any]) {
        // Parse scalars safely (JSONSerialization may return NSNumber)
        func parseInt(_ key: String) -> Int {
            (json[key] as? Int) ?? Int(json[key] as? Double ?? 0)
        }
        func parseFloat(_ key: String, _ fallback: Double) -> Float {
            Float(json[key] as? Double ?? fallback)
        }

        globalMean = parseFloat("globalMean", 0)
        nFactors   = parseInt("n_factors")
        nUsers     = parseInt("n_users")
        ratingMin  = parseFloat("rating_min", 5.0)
        ratingMax  = parseFloat("rating_max", 10.0)

        // item_factors may be flat [Double] or nested [[Double]]
        func parseFactors(_ key: String) -> [Float] {
            if let flat   = json[key] as? [Double]   { return flat.map { Float($0) } }
            if let nested = json[key] as? [[Double]]  { return nested.flatMap { $0 }.map { Float($0) } }
            return []
        }

        userFactors = parseFactors("user_factors")
        itemFactors = parseFactors("item_factors")
        userBiases  = (json["user_biases"] as? [Double] ?? []).map { Float($0) }
        itemBiases  = (json["item_biases"] as? [Double] ?? []).map { Float($0) }

        userMap = json["user_map"] as? [String: Int] ?? [:]
        itemMap = json["item_map"] as? [String: Int] ?? [:]

        var rev = [Int: String]()
        rev.reserveCapacity(itemMap.count)
        for (isbn, idx) in itemMap { rev[idx] = isbn }
        itemReverseMap = rev

        itemsWithFactorData = nFactors > 0 ? itemFactors.count / nFactors : 0

        // ── Normalised ISBN lookup (handles leading-zero / ISBN-10/13 variants)
        var norm = [String: Int]()
        norm.reserveCapacity(itemMap.count * 3)
        for (isbn, idx) in itemMap {
            norm[isbn] = idx
            let s = Self.stripLeadingZeros(isbn)
            norm[s] = idx
            if isbn.count == 13 {
                if let ten = Self.isbn13to10(isbn) {
                    norm[ten] = idx
                    norm[Self.stripLeadingZeros(ten)] = idx
                }
            } else if isbn.count <= 10 {
                let thirteen = Self.isbn10to13(isbn)
                norm[thirteen] = idx
                norm[Self.stripLeadingZeros(thirteen)] = idx
            }
        }
        normalisedItemMap = norm

        // ── Compute average L2 norm of trained user vectors
        // This is used to scale fold-in (cold-start) vectors to the same
        // magnitude as trained vectors, so dot products are comparable.
        let n = nFactors > 0 ? userFactors.count / nFactors : 0
        var totalNorm: Float = 0
        for uid in 0..<n {
            let start = uid * nFactors
            guard start + nFactors <= userFactors.count else { continue }
            var sumSq: Float = 0
            vDSP_svesq(
                Array(userFactors[start..<start + nFactors]),
                1, &sumSq, vDSP_Length(nFactors)
            )
            totalNorm += sqrt(sumSq)
        }
        avgUserNorm = n > 0 ? totalNorm / Float(n) : 1.0
    }

    // MARK: – Public
    func userExists(_ userId: String) -> Bool { userMap[userId] != nil }

    func resolveItemIndex(_ isbn: String) -> Int? {
        normalisedItemMap[isbn] ?? normalisedItemMap[Self.stripLeadingZeros(isbn)]
    }

    // MARK: – Case 1: Recommend for a known (trained) user
    //
    // Blend weight α grows with session rating count:
    //   α = min(0.8, sessionRatingCount × 0.15)
    //   0 ratings  → α = 0.00 → 100% pre-trained  (personalized from history)
    //   1 rating   → α = 0.15 → small taste shift
    //   3 ratings  → α = 0.45 → moderate shift
    //   5+ ratings → α = 0.75 → strong shift toward new session behavior
    func recommend(
        userId:       String,
        sessionRatings: [String: Float],
        excludeISBNs: Set<String> = [],
        n:            Int = 20
    ) -> [(isbn: String, score: Float)] {

        guard let uid = userMap[userId] else { return [] }
        let uStart = uid * nFactors
        guard uStart + nFactors <= userFactors.count else { return [] }

        let uVec  = Array(userFactors[uStart..<uStart + nFactors])
        let uBias = userBiases[uid]
        
        // Build effective vector that blend base with fold-in if session ratings exist
        var effectiveVec = uVec
        let newRatings = sessionRatings.filter { resolveItemIndex($0.key) != nil }
        
        if !newRatings.isEmpty {
            // Compute fold-in vector from session ratings
            if let foldInVec = buildFoldInVector(from: newRatings) {
                // α grows per new rating, capped at 0.8 so pre-trained history
                // never fully disappears
                let alpha = min(0.8, Float(newRatings.count) * 0.15)
                
                // effectiveVec = (1 - α) × base + α × foldIn
                var blended = [Float](repeating: 0, count: nFactors)
                let oneMinusAlpha = 1.0 - alpha
                
                // (1 - α) × baseVec
                var scaledBase = [Float](repeating: 0, count: nFactors)
                vDSP_vsmul(uVec, 1, [oneMinusAlpha], &scaledBase, 1, vDSP_Length(nFactors))
                
                // α × foldInVec
                var scaledFold = [Float](repeating: 0, count: nFactors)
                vDSP_vsmul(foldInVec, 1, [alpha], &scaledFold, 1, vDSP_Length(nFactors))
                
                vDSP_vadd(scaledBase, 1, scaledFold, 1, &blended, 1, vDSP_Length(nFactors))
                effectiveVec = blended
                
                print("🔀 Blending: \(newRatings.count) session ratings, α=\(String(format:"%.2f", alpha))")
            }
        }

        // Temporary tuple: (isbn, displayScore, personalDot)
        var items = [(isbn: String, display: Float, dot: Float)]()
        items.reserveCapacity(itemsWithFactorData)

        for iid in 0..<itemsWithFactorData {
            guard let isbn = itemReverseMap[iid]   else { continue }
            if excludeISBNs.contains(isbn)         { continue }
            guard iid < itemBiases.count           else { continue }

            let iStart = iid * nFactors
            let iVec   = Array(itemFactors[iStart..<iStart + nFactors])

            var dot: Float = 0
            vDSP_dotpr(effectiveVec, 1, iVec, 1, &dot, vDSP_Length(nFactors))

            let display = min(max(
                globalMean + uBias + itemBiases[iid] + dot,
                ratingMin), ratingMax)

            items.append((isbn: isbn, display: display, dot: dot))
        }

        // Sort by personal dot product — this is the user-specific signal.
        // Items with high dot mean "this book's latent features align with
        // this user's latent taste vector", regardless of global popularity.
        items.sort { $0.dot > $1.dot }

        return Array(items.prefix(n)).map { (isbn: $0.isbn, score: $0.display) }
    }

    // MARK: – Case 2: Fold-in for new user
    //
    // Key fix: after building the weighted-average item vector, we scale
    // it to match avgUserNorm. Without this, the vector has magnitude ~0.02
    // while trained vectors are ~1.8, making dot products ~100x smaller than
    // item biases — every user gets the same "most popular" ranking.
    func approximateAndRecommend(
            ratedBooks:   [String: Float],
            excludeISBNs: Set<String> = [],
            n:            Int = 20
        ) -> [(isbn: String, score: Float)] {
     
            guard !ratedBooks.isEmpty else { return [] }
            guard let userVec = buildFoldInVector(from: ratedBooks) else {
                print("⚠️ Fold-in: no valid rated items found in item_map")
                return []
            }
     
            let validCount  = ratedBooks.filter { resolveItemIndex($0.key) != nil }.count
            let avgItemBias = ratedBooks.compactMap { resolveItemIndex($0.key).map { itemBiases[$0] } }
                                        .reduce(0, +) / Float(max(validCount, 1))
     
            print("🔍 Fold-in: \(validCount)/\(ratedBooks.count) rated ISBNs found in item_map")
     
            var items = [(isbn: String, display: Float, dot: Float)]()
            items.reserveCapacity(itemsWithFactorData)
     
            for iid in 0..<itemsWithFactorData {
                guard let isbn = itemReverseMap[iid] else { continue }
                if excludeISBNs.contains(isbn) { continue }
                if ratedBooks[isbn] != nil      { continue }
                guard iid < itemBiases.count    else { continue }
     
                let iStart = iid * nFactors
                let iVec   = Array(itemFactors[iStart..<iStart + nFactors])
     
                var dot: Float = 0
                vDSP_dotpr(userVec, 1, iVec, 1, &dot, vDSP_Length(nFactors))
     
                let display = min(max(
                    globalMean + avgItemBias + itemBiases[iid] + dot,
                    ratingMin), ratingMax)
     
                items.append((isbn: isbn, display: display, dot: dot))
            }
     
            items.sort { $0.dot > $1.dot }
            print("   Fold-in pool: \(items.count) items")
            return Array(items.prefix(n)).map { (isbn: $0.isbn, score: $0.display) }
        }
     
        // MARK: – Shared fold-in vector builder
        // Builds a user vector from a set of rated books, scaled to avgUserNorm.
        // Used by both Case 1 (as the adjustment component) and Case 2 (standalone).
        private func buildFoldInVector(from ratedBooks: [String: Float]) -> [Float]? {
            var weightedSum = [Float](repeating: 0, count: nFactors)
            var totalWeight: Float = 0
            var validCount  = 0
     
            for (isbn, rating) in ratedBooks {
                guard let iid = resolveItemIndex(isbn),
                      iid < itemsWithFactorData,
                      iid < itemBiases.count
                else { continue }
     
                let iStart = iid * nFactors
                let iVec   = Array(itemFactors[iStart..<iStart + nFactors])
     
                // Weight encodes preference direction:
                // positive = user likes this type; negative = user dislikes
                let weight = rating - globalMean
                var scaled = [Float](repeating: 0, count: nFactors)
                vDSP_vsmul(iVec, 1, [weight], &scaled, 1, vDSP_Length(nFactors))
                vDSP_vadd(weightedSum, 1, scaled, 1, &weightedSum, 1, vDSP_Length(nFactors))
     
                totalWeight += abs(weight)
                validCount  += 1
            }
     
            guard validCount > 0, totalWeight > 0 else { return nil }
     
            // Normalise direction
            var vec = [Float](repeating: 0, count: nFactors)
            vDSP_vsmul(weightedSum, 1, [1.0 / totalWeight], &vec, 1, vDSP_Length(nFactors))
     
            // Scale magnitude to avgUserNorm so dot products are comparable to
            // those of trained users — without this, dot ≈ 0.02 and item biases
            // dominate the ranking (same top books for every user)
            var sumSq: Float = 0
            vDSP_svesq(vec, 1, &sumSq, vDSP_Length(nFactors))
            let norm = sqrt(sumSq)
            if norm > 1e-6 {
                vDSP_vsmul(vec, 1, [avgUserNorm / norm], &vec, 1, vDSP_Length(nFactors))
            }
     
            return vec
        }
     
        // MARK: – ISBN normalisation
        private static func stripLeadingZeros(_ s: String) -> String {
            String(s.drop(while: { $0 == "0" }))
        }
        private static func isbn13to10(_ s: String) -> String? {
            let d = s.filter(\.isNumber)
            guard d.count == 13, d.hasPrefix("978") else { return nil }
            let nine = String(d.dropFirst(3).prefix(9))
            guard nine.count == 9 else { return nil }
            var sum = 0
            for (i, c) in nine.enumerated() { sum += (c.wholeNumberValue ?? 0) * (10 - i) }
            let check = (11 - sum % 11) % 11
            return nine + (check == 10 ? "X" : String(check))
        }
        private static func isbn10to13(_ s: String) -> String {
            let d    = s.filter { $0.isNumber || $0 == "X" || $0 == "x" }
            let nine = String(d.prefix(9))
            let body = "978" + nine
            let sum  = body.enumerated().reduce(0) {
                $0 + ($1.element.wholeNumberValue ?? 0) * ($1.offset % 2 == 0 ? 1 : 3)
            }
            return body + String((10 - sum % 10) % 10)
        }
    }
