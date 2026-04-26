//
//  HomeView.swift
//  BookRecommendation
//
//  Created by Vira Fitriyani on 23/04/26.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var session: UserSessionModel
    @EnvironmentObject var engine:  RecommendationEngine

    @State private var searchText = ""
    @State private var isSearchActive = false

    var searchResults: [Book] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return Array(
            engine.booksMeta.values
                .filter {
                    $0.title.lowercased().contains(q) ||
                    $0.author.lowercased().contains(q)
                }
                .sorted { $0.title < $1.title }
                .prefix(30)
        )
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !isSearchActive {
                    ModeBannerView(mode: engine.mode,
                                   ratingCount: session.ratingCount)
                }

                if engine.isLoading && searchText.isEmpty {
                    Spacer()
                    ProgressView("Finding books...")
                    Spacer()
                } else if isSearchActive {
                    searchList
                } else {
                    recommendationList
                }
            }
            .navigationTitle("For You")
            .searchable(text: $searchText, isPresented: $isSearchActive, prompt: "Search books to rate...")
        }
        .onAppear {
            engine.refresh(session: session)
        }
    }

    // MARK: – Search
    private var searchList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if searchResults.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle).foregroundColor(.secondary)
                        Text("No results for \(searchText)")
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(searchResults) { book in
                        BookCardView(
                            book: book,
                            isRated: session.hasRated(isbn: book.isbn),
                            userRating: session.sessionRatings[book.isbn]
                        ) { rating in
                            session.rateBook(isbn: book.isbn, rating: rating)
                            searchText = ""
                            isSearchActive = false
                            engine.refresh(session: session)
                        }
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: – Recommendations
    private var recommendationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(engine.books) { book in
                    BookCardView(
                        book: book,
                        isRated: session.hasRated(isbn: book.isbn),
                        userRating: session.sessionRatings[book.isbn]
                    ) { rating in
                        session.rateBook(isbn: book.isbn, rating: rating)
                        engine.refresh(session: session)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .opacity
                    ))
                    Divider()
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8),
                       value: engine.books)

            VStack(spacing: 0) {
                Divider()
                    .padding(.bottom, 8)

                Button {
                    engine.exploreMore(session: session)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle")
                            .font(.title3)
                        Text("Explore More Books")
                            .fontWeight(.semibold)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                }
                .foregroundColor(.blue)
                .contentShape(Rectangle())
                .padding(.vertical, 12)
            }
            .padding(.top, 4)
        }
        .refreshable {
            engine.refresh(session: session, isUserInitiated: true)
        }
    }
}
