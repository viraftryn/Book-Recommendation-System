//
//  SVDEngine.swift
//  
//
//  Created by Vira Fitriyani on 22/04/26.
//

import Foundation
import Accelerate

class SVDEngine {
    // Model parameters
    let globalMean: Float
    let nFactors: Int
    let nUsers: Int
    let nItems: Int
    let ratingMin: Float
    let ratingMax: Float
    
    // Contiguous arrays for accelerate
    private let userFactors: [Float]
    private let itemFactors: [Float]
    private let userBiases: [Float]
    private let itemBiases: [Float]
    
    // ID mappings
    let userMap: [String: Int]
    let itemMap: [String: Int]
    
    // Reverse item map for index (isbn lookup)
    private let itemReverseMap: [Int: String]
    
    // Load SVD Model
    static func load() -> SVDEngine? {
        guard let url = Bundle.main.url(
            forResource: "svd_model_export",
            withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        
        guard let json = try? JSONSerialization.jsonObject(
            with: data) as? [String: Any]
        else { return nil }
        
        return SVDEngine(json: json)
    }
    
    private init(json: [String: Any]){
        globalMean = Float(json["globalMean"] as? Double ?? 0)
        nFactors = json["n_factors"] as? Int ?? 0
        nUsers = json["n_users"] as? Int ?? 0
        nItems = json["n_items"] as? Int ?? 0
        ratingMin = Float(json["rating_min"] as? Double ?? 5.0)
        ratingMax = Float(json["rating_max"] as? Double ?? 10.0)
        
        // Convert double arrays to float for accelerate
        let UFRaw = json["user_factors"] as? [Double] ?? []
        let IFRaw = json["item_factors"] as? [Double] ?? []
        let UBRaw = json["user_biases"] as? [Double] ?? []
        let IBRaw = json["item_biases"] as? [Double] ?? []
        
        userFactors = UFRaw.map{ Float($0) }
        itemFactors = IFRaw.map{ Float($0) }
        userBiases = UBRaw.map{ Float($0) }
        itemBiases = IBRaw.map{ Float($0) }
        
        userMap = json["user_map"] as? [String: Int] ?? [:]
        itemMap = json["item_map"] as? [String: Int] ?? [:]
        
        // Build reverse map
        var rev = [Int: String]()
        for (isbn, idx) in itemMap { rev[idx] = isbn}
        itemReverseMap = rev
    }
    
    // Check if user exists in the model
    func userExists(_ userId: String) -> Bool {
        return userMap[userId] != nil
    }
    
    // Get item vector
    func itemVector(for isbn: String) -> [Float]? {
        guard let iid = itemMap[isbn] else { return nil }
        let start = iid * nFactors
        return Array(itemFactors[start..<start + nFactors])
    }
    
    // Predict Rating
    func predict(userId: String, isbn: String) -> Float? {
        guard let uid = userMap[userId],
              let iid = itemMap[isbn]
        else { return nil }
        
        return predictByIndex(uid: uid, iid: iid)
    }
    
    // Internal prediction index
    private func predictByIndex(uid: Int, iid: Int) -> Float {
        let uStart = uid * nFactors
        let iStart = iid * nFactors
        
        let uVec = Array(userFactors[uStart..<uStart + nFactors])
        let iVec = Array(itemFactors[iStart..<iStart + nFactors])
        
        // vDSP dot product
        var dot: Float = 0
        vDSP_dotpr(uVec, 1, iVec, 1, &dot, vDSP_Length(nFactors))
        
        let pred = globalMean
        + userBiases[uid]
        + itemBiases[iid]
        + dot
        
        return min(max(pred, ratingMin), ratingMax)
    }
    
    // Full recommendations for known user
    func recommend(
        userId:       String,
        excludeISBNs: Set<String> = [],
        n: Int = 10
    ) -> [(isbn: String, score: Float)] {
        
        guard let uid = userMap[userId] else { return [] }
        
        let uStart = uid * nFactors
        let uVec   = Array(userFactors[uStart..<uStart + nFactors])
        let uBias  = userBiases[uid]
        
        var scores = [(isbn: String, score: Float)]()
        scores.reserveCapacity(nItems)
        
        for iid in 0..<nItems {
            guard let isbn = itemReverseMap[iid] else { continue }
            if excludeISBNs.contains(isbn) { continue }
            
            let iStart = iid * nFactors
            let iVec   = Array(itemFactors[iStart..<iStart + nFactors])
            
            var dot: Float = 0
            vDSP_dotpr(uVec, 1, iVec, 1, &dot, vDSP_Length(nFactors))
            
            let score = min(max(
                globalMean + uBias + itemBiases[iid] + dot,
                ratingMin), ratingMax)
            
            scores.append((isbn: isbn, score: score))
        }
        
        scores.sort { $0.score > $1.score }
        return Array(scores.prefix(n))
    }
    
    // Fold in: approximate vector for new user
    func approximateAndRecommend(
        ratedBooks:   [String: Float],
        excludeISBNs: Set<String> = [],
        n: Int = 10
    ) -> [(isbn: String, score: Float)] {
        
        guard !ratedBooks.isEmpty else { return [] }
        
        // Build approximate user vector
        // user_vec ≈ weighted average of rated item vectors
        var weightedSum = [Float](repeating: 0, count: nFactors)
        var totalWeight: Float = 0
        var approxBias:  Float = 0
        var validCount   = 0
        
        for (isbn, rating) in ratedBooks {
            guard let iid = itemMap[isbn] else { continue }
            
            let iStart = iid * nFactors
            let iVec   = Array(itemFactors[iStart..<iStart + nFactors])
            
            // Weight = deviation from global mean
            // High rating → positive contribution
            // Low rating  → negative contribution
            let weight = rating - globalMean
            
            // Accumulate: weightedSum += weight * itemVector
            var scaled = [Float](repeating: 0, count: nFactors)
            vDSP_vsmul(iVec, 1, [weight], &scaled, 1,
                       vDSP_Length(nFactors))
            vDSP_vadd(weightedSum, 1, scaled, 1,
                      &weightedSum, 1, vDSP_Length(nFactors))
            
            totalWeight += abs(weight)
            approxBias  += itemBiases[iid]
            validCount  += 1
        }
        
        guard validCount > 0, totalWeight > 0 else { return [] }
        
        // Normalize user vector
        var userVec = [Float](repeating: 0, count: nFactors)
        let norm = 1.0 / totalWeight
        vDSP_vsmul(weightedSum, 1, [norm], &userVec, 1,
                   vDSP_Length(nFactors))
        
        // Average item bias as proxy for unknown user bias
        let avgItemBias = approxBias / Float(validCount)
        
        // Step 2: score all unrated items with approximated vector
        var scores = [(isbn: String, score: Float)]()
        scores.reserveCapacity(nItems)
        
        for iid in 0..<nItems {
            guard let isbn = itemReverseMap[iid] else { continue }
            if excludeISBNs.contains(isbn) { continue }
            if ratedBooks[isbn] != nil     { continue }
            
            let iStart = iid * nFactors
            let iVec   = Array(itemFactors[iStart..<iStart + nFactors])
            
            var dot: Float = 0
            vDSP_dotpr(userVec, 1, iVec, 1, &dot, vDSP_Length(nFactors))
            
            let score = min(max(
                globalMean + avgItemBias + itemBiases[iid] + dot,
                ratingMin), ratingMax)
            
            scores.append((isbn: isbn, score: score))
        }
        scores.sort { $0.score > $1.score }
        return Array(scores.prefix(n))
    }
}
