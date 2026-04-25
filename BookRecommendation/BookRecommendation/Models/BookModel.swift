//
//  BookModel.swift
//
//
//  Created by Vira Fitriyani on 22/04/26.
//

import Foundation

struct Book: Codable, Identifiable, Equatable {
    var id: String { isbn }
    let isbn: String
    let title: String
    let author: String
    let year: Int?
    let publisher: String?
    var score: Double? = nil
    
    enum CodingKeys: String, CodingKey {
        case isbn, title, author, year, publisher
    }
    
    var coverURL: URL? {
        URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-M.jpg")
    }
    
    var scoreLabel: String {
        guard let score = score else { return "Suggested" }
        
        switch score {
        case 9.0...: return "Must Read"
        case 8.0...: return "Great Pick"
        case 7.0...: return "Good Read"
        default: return "Suggested"
        }
    }
}
