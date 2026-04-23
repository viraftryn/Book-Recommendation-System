//
//  BookCardView.swift
//  BookRecommendation
//
//  Created by Vira Fitriyani on 23/04/26.
//

import SwiftUI

struct BookCardView: View {
    let book:       Book
    let isRated:    Bool
    let userRating: Float?
    let onRate:     (Float) -> Void
    
    @State private var showRatingSheet = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Book cover
            AsyncImage(url: book.coverURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                       .aspectRatio(contentMode: .fill)
                       .frame(width: 60, height: 85)
                       .cornerRadius(6)
                       .clipped()
                case .failure, .empty:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 60, height: 85)
                        .overlay(
                            Text(String(book.title.prefix(1)))
                                .font(.title)
                                .foregroundColor(.blue)
                        )
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 60, height: 85)
            
            // Book info
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                
                Text(book.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack {
                    Text(book.scoreLabel)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    
                    Spacer()
                    
                    // Show user's rating if rated
                    if let rating = userRating {
                        Label(String(format: "%.0f/10", rating),
                              systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            // Rate button
            Button {
                showRatingSheet = true
            } label: {
                Image(systemName: isRated
                      ? "star.fill"
                      : "star")
                    .foregroundColor(isRated ? .yellow : .gray)
                    .font(.title2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .sheet(isPresented: $showRatingSheet) {
            RatingSheet(book: book, onRate: { rating in
                onRate(rating)
                showRatingSheet = false
            })
            .presentationDetents([.fraction(0.45)])
        }
    }
}
