//
//  ProfileView.swift
//  BookRecommendation
//
//  Created by Vira Fitriyani on 23/04/26.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var session: UserSessionModel
    @EnvironmentObject var engine:  RecommendationEngine
 
    @State private var showLogoutAlert = false
 
    var ratedBooks: [RatedBookEntry] {
        session.sessionRatings
            .compactMap { isbn, rating -> RatedBookEntry? in
                guard let book = engine.booksMeta[isbn] else { return nil }
                return RatedBookEntry(book: book, rating: rating)
            }
            .sorted { $0.rating > $1.rating }
    }
 
    var body: some View {
        NavigationView {
            List {
                // MARK: – User info section
                Section {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            )
 
                        VStack(alignment: .leading, spacing: 4) {
                            Text("User \(session.userId)")
                                .font(.headline)
 
                            Text(session.isNewUser
                                 ? "You don't have any ratings yet."
                                 : "ID: \(session.userId)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
 
                // MARK: – Stats
                Section {
                    HStack {
                        StatCell(value: "\(session.ratingCount)",
                                 label: "Books Rated",
                                 icon: "star.fill",
                                 color: .yellow)
                        Divider()
                        StatCell(value: averageRatingLabel,
                                 label: "Avg Rating",
                                 icon: "chart.bar.fill",
                                 color: .blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
 
                // MARK: – Rating history
                Section {
                    if ratedBooks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "books.vertical")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No ratings yet")
                                .foregroundColor(.secondary)
                            Text("Tap any book card to rate it")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(ratedBooks) { entry in
                            RatedBookRow(entry: entry)
                        }
                    }
                } header: {
                    Text("My Ratings")
                }
 
                // MARK: – Logout
                Section {
                    Button(role: .destructive) {
                        showLogoutAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Log Out")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .alert("Log Out?", isPresented: $showLogoutAlert) {
                Button("Log Out", role: .destructive) {
                    session.logout()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(session.isNewUser
                     ? "Your ratings will be lost."
                     : "Your ratings are saved and will be here when you return.")
            }
        }
    }
 
    // Highest rated book's score as a label
    private var topScoreLabel: String {
        guard let top = ratedBooks.first else { return "–" }
        return "\(Int(top.rating))/10"
    }
 
    private var averageRatingLabel: String {
        guard !session.sessionRatings.isEmpty else { return "–" }
        let avg = session.sessionRatings.values.reduce(0, +)
                  / Float(session.sessionRatings.count)
        return String(format: "%.1f", avg)
    }
}
 
// MARK: – Sub-views
 
struct RatedBookEntry: Identifiable {
    let book:   Book
    let rating: Float
    var id: String { book.isbn }
}
 
private struct RatedBookRow: View {
    let entry: RatedBookEntry
 
    var body: some View {
        HStack(spacing: 12) {
            // Cover thumbnail
            AsyncImage(url: entry.book.coverURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                       .aspectRatio(contentMode: .fill)
                       .frame(width: 44, height: 62)
                       .cornerRadius(5)
                       .clipped()
                default:
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 44, height: 62)
                        .overlay(
                            Text(String(entry.book.title.prefix(1)))
                                .font(.headline)
                                .foregroundColor(.blue)
                        )
                }
            }
 
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.book.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
 
                Text(entry.book.author)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
 
                // Star row — filled up to user's rating (out of 10, shown as /5 stars)
                StarsView(rating: entry.rating)
            }
 
            Spacer()
 
            // Numeric badge
            VStack(spacing: 2) {
                Text("\(Int(entry.rating))")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(ratingColor(entry.rating))
                Text("/ 10")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
 
    private func ratingColor(_ r: Float) -> Color {
        switch r {
        case 9...: return .green
        case 7...: return .blue
        case 5...: return .orange
        default:   return .red
        }
    }
}
 
// 5 stars, half-filled based on a 1–10 rating
private struct StarsView: View {
    let rating: Float            // 1–10
 
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                let threshold = Float(star * 2)   // each star = 2 points
                Image(systemName: rating >= threshold
                      ? "star.fill"
                      : (rating >= threshold - 1 ? "star.leadinghalf.filled" : "star"))
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
        }
    }
}
 
private struct StatCell: View {
    let value: String
    let label: String
    let icon:  String
    let color: Color
 
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.subheadline)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
