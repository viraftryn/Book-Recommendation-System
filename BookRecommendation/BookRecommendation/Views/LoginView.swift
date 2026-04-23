//
//  LoginView.swift
//  
//
//  Created by Vira Fitriyani on 23/04/26.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: UserSessionModel
    @State private var userIdInput = ""
    @State private var showError = false
    
    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Book Recommender")
                    .font(.largeTitle).bold()
                
                Text("Discover books you'll love")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 60)
            
            Spacer()
            
            VStack(spacing: 16) {
                // Existing user login
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in with User ID")
                        .font(.headline)
                    
                    HStack {
                        TextField("Enter your User ID",
                                  text: $userIdInput)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        
                        Button("Sign In") {
                            session.login(
                                mode: .existingUser(userIdInput))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(userIdInput.isEmpty)
                    }
                    
                    if showError {
                        Text("User ID not found — "
                             + "try continuing as new user")
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }
                
                // Divider
                HStack {
                    Rectangle().frame(height: 1)
                        .foregroundColor(.gray.opacity(0.3))
                    Text("or").foregroundColor(.secondary)
                    Rectangle().frame(height: 1)
                        .foregroundColor(.gray.opacity(0.3))
                }
                
                // New user
                Button {
                    session.login(mode: .newUser)
                } label: {
                    Label("Continue as New User",
                          systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
    }
}

#Preview {
    LoginView()
}
