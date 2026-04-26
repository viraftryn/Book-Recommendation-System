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
    // Sorting key: dot(userVec, itemVec)
    //   — the purely personal preference component.
    //   itemBias is identical for every user, so using it as a sort key
    //   produces the same ranking for everyone. By sorting on dot product
    //   only we ensure each user's tastes drive the order.
    //
    // Stored score: full SVD formula (for UI display).
    func recommend(
        userId:       String,
        excludeISBNs: Set<String> = [],
        n:            Int = 20
    ) -> [(isbn: String, score: Float)] {

        guard let uid = userMap[userId] else { return [] }
        let uStart = uid * nFactors
        guard uStart + nFactors <= userFactors.count else { return [] }

        let uVec  = Array(userFactors[uStart..<uStart + nFactors])
        let uBias = userBiases[uid]

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
            vDSP_dotpr(uVec, 1, iVec, 1, &dot, vDSP_Length(nFactors))

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

    // MARK: – Case 2: Fold-in for new / guest user
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

        // Step 1: weighted sum of rated item vectors
        var weightedSum = [Float](repeating: 0, count: nFactors)
        var totalWeight: Float = 0
        var approxBias:  Float = 0
        var validCount   = 0
        var missed       = [String]()

        for (isbn, rating) in ratedBooks {
            guard let iid = resolveItemIndex(isbn),
                  iid < itemsWithFactorData,
                  iid < itemBiases.count
            else { missed.append(isbn); continue }

            let iStart = iid * nFactors
            let iVec   = Array(itemFactors[iStart..<iStart + nFactors])

            // Weight = deviation from globalMean.
            // Positive weight → user likes this type of book.
            // Negative weight → user dislikes this type of book.
            let weight = rating - globalMean

            var scaled = [Float](repeating: 0, count: nFactors)
            vDSP_vsmul(iVec, 1, [weight], &scaled, 1, vDSP_Length(nFactors))
            vDSP_vadd(weightedSum, 1, scaled, 1, &weightedSum, 1, vDSP_Length(nFactors))

            totalWeight += abs(weight)
            approxBias  += itemBiases[iid]
            validCount  += 1
        }

        guard validCount > 0, totalWeight > 0 else {
            return []
        }

        // Step 2: normalise by totalWeight → unit-direction vector
        var userVec = [Float](repeating: 0, count: nFactors)
        vDSP_vsmul(weightedSum, 1, [1.0 / totalWeight], &userVec, 1, vDSP_Length(nFactors))

        // Step 3: RE-SCALE to avgUserNorm
        // Without this, the vector's L2 norm is ~0.02 vs ~1.8 for trained users.
        // That makes dot products 90x smaller than item biases, so ranking
        // degenerates to "sort by item popularity" for every user.
        var sumSq: Float = 0
        vDSP_svesq(userVec, 1, &sumSq, vDSP_Length(nFactors))
        let currentNorm = sqrt(sumSq)
        if currentNorm > 1e-6 {
            let scale = avgUserNorm / currentNorm
            vDSP_vsmul(userVec, 1, [scale], &userVec, 1, vDSP_Length(nFactors))
        }

        let avgItemBias = approxBias / Float(validCount)

        // Step 4: score all unrated items
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

        // Sort by personal dot product, same reasoning as Case 1
        items.sort { $0.dot > $1.dot }

        return Array(items.prefix(n)).map { (isbn: $0.isbn, score: $0.display) }
    }

    // MARK: – ISBN normalisation helpers
    private static func stripLeadingZeros(_ isbn: String) -> String {
        String(isbn.drop(while: { $0 == "0" }))
    }

    private static func isbn13to10(_ isbn13: String) -> String? {
        let digits = isbn13.filter(\.isNumber)
        guard digits.count == 13, digits.hasPrefix("978") else { return nil }
        let nine = String(digits.dropFirst(3).prefix(9))
        guard nine.count == 9 else { return nil }
        var sum = 0
        for (i, ch) in nine.enumerated() {
            guard let d = ch.wholeNumberValue else { return nil }
            sum += d * (10 - i)
        }
        let check = (11 - (sum % 11)) % 11
        return nine + (check == 10 ? "X" : String(check))
    }

    private static func isbn10to13(_ isbn10: String) -> String {
        let digits = isbn10.filter { $0.isNumber || $0 == "X" || $0 == "x" }
        let nine   = String(digits.prefix(9))
        let body   = "978" + nine
        let sum    = body.enumerated().reduce(0) { acc, pair in
            acc + (pair.element.wholeNumberValue ?? 0) * (pair.offset % 2 == 0 ? 1 : 3)
        }
        return body + String((10 - (sum % 10)) % 10)
    }
}
