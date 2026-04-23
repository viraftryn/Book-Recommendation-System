//
//  ModeBannerView.swift
//  BookRecommendation
//
//  Created by Vira Fitriyani on 23/04/26.
//

import SwiftUI

struct ModeBannerView: View {
    let mode:        RecommendationMode
    let ratingCount: Int
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundColor(bannerColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.description)
                    .font(.subheadline).bold()
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(bannerColor.opacity(0.1))
    }
    
    private var iconName: String {
        switch mode {
        case .popular:      return "flame"
        case .coldStart:    return "sparkles"
        case .personalized: return "star.fill"
        }
    }
    
    private var bannerColor: Color {
        switch mode {
        case .popular:      return .orange
        case .coldStart:    return .blue
        case .personalized: return .green
        }
    }
    
    private var subtitle: String {
        switch mode {
        case .popular:
            return "Rate a book to personalize your feed"
        case .coldStart(let n):
            return n < 3
            ? "Rate \(3 - n) more book\(3-n == 1 ? "" : "s") "
            + "to improve recommendations"
            : "Recommendations improving as you rate more"
        case .personalized:
            return "Tailored to your taste"
        }
    }
}

#Preview {
    ModeBannerView(mode: .coldStart(3), ratingCount: 3)
}