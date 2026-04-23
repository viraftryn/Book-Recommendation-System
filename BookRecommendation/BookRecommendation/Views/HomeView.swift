//
//  HomeView.swift
//  BookRecommendation
//
//  Created by Vira Fitriyani on 23/04/26.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var session: UserSessionModel
    @StateObject private var engine = RecommendationEngine()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                
                // Mode banner — tells user why they see these
                ModeBannerView(mode: engine.mode,
                               ratingCount: session.ratingCount)
                
                if engine.isLoading {
                    Spacer()
                    ProgressView("Finding books...")
                    Spacer()
                    
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(engine.books) { book in
                                BookCardView(
                                    book:       book,
                                    isRated:    session.hasRated(
                                        isbn: book.isbn),
                                    userRating: session
                                        .sessionRatings[book.isbn]
                                ) { rating in
                                    // User rated a book — immediate refresh
                                    session.rateBook(
                                        isbn:   book.isbn,
                                        rating: rating)
                                    engine.refresh(session: session)
                                }
                                Divider()
                            }
                        }
                    }
                    .refreshable {
                        engine.refresh(session: session)
                    }
                }
            }
            .navigationTitle("For You")
        }
        .onAppear {
            engine.refresh(session: session)
        }
    }
}

#Preview {
    HomeView()
}
