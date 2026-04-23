//
//  RatingSheet.swift
//  BookRecommendation
//
//  Created by Vira Fitriyani on 23/04/26.
//

import SwiftUI

struct RatingSheet: View {
    let book:   Book
    let onRate: (Float) -> Void
    
    @State private var selectedRating: Float = 8.0
    
    // Quick rating options
    private let quickRatings: [(label: String,
                                icon: String,
                                value: Float)] = [
        ("Not for me",  "hand.thumbsdown", 5.0),
        ("It was okay", "minus.circle",    7.0),
        ("Liked it",    "hand.thumbsup",   8.0),
        ("Loved it!",   "heart.fill",     10.0)
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // Book title
            Text(book.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.top)
            
            // Quick rate buttons
            HStack(spacing: 12) {
                ForEach(quickRatings, id: \.label) { option in
                    Button {
                        onRate(option.value)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: option.icon)
                                .font(.title2)
                            Text(option.label)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal)
            
            // Fine-grained slider
            VStack(spacing: 8) {
                Text("Or rate precisely: \(Int(selectedRating))/10")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Slider(value: $selectedRating,
                       in: 1...10, step: 1)
                    .padding(.horizontal)
                
                Button("Submit Rating") {
                    onRate(selectedRating)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.bottom)
    }
}
