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
    @State private var newUserId = ""
    @State private var showError = false
    @State private var showNewUserId = false
    
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
                        TextField("Enter your numeric User ID",
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
                if showNewUserId {
                    VStack(spacing: 12) {
                        Text("Your new User ID")
                            .font(.headline)
                        
                        Text(newUserId)
                            .font(.system(.title2, design: .monospaced))
                            .bold()
                            .foregroundColor(.blue)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(10)
                        
                        Text("Save this ID - you can use it to log back in")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                        
                        Button("Continue") {
                            session.login(mode: .existingUser(newUserId))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .background(Color.blue.opacity(0.04))
                    .cornerRadius(12)
                } else {
                    Button {
                        // Generate the ID
                        let id = String(Int.random(in: 100_000...999_999))
                        newUserId = id
                        
                        showNewUserId = true
                    } label: {
                        Label("Create New Account", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
    }
}

#Preview {
    LoginView()
}
