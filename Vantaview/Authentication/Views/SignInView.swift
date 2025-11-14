//
//  SignInView.swift
//  Vantaview
//
//  Created by Vantaview on 12/19/24.
//

import SwiftUI

struct SignInView: View {
    @ObservedObject var authManager: AuthenticationManager
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingErrorAlert = false
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // App Logo/Title
            VStack(spacing: 16) {
                Image(systemName: "video.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Vantaview")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Professional Live Video Production")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            // Sign In Options
            VStack(spacing: 16) {

                // Sign in via Website (Primary method)
                Button(action: {
                    signInViaWebsite()
                }) {
                    HStack {
                        Image(systemName: "safari")
                        Text("Sign in via Browser")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)

                Text("Opens vantaview.live in your browser")
                    .font(.caption)
                    .foregroundColor(.secondary)

            }
            .frame(maxWidth: 280)
            
            if isLoading {
                ProgressView("Signing in...")
                    .progressViewStyle(CircularProgressViewStyle())
            }
            
            Spacer()
            
            // Terms and Privacy
            VStack(spacing: 8) {
                Text("By signing in, you agree to our")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    Button("Terms of Service") {
                        // TODO: Open terms URL
                    }
                    .font(.caption)
                    
                    Button("Privacy Policy") {
                        // TODO: Open privacy URL
                    }
                    .font(.caption)
                }
            }
        }
        .padding(40)
        .alert("Sign In Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }
    
    private func signInViaWebsite() {
        // Open the website with a query parameter to indicate app sign-in
        if let url = URL(string: "https://vantaview.live/?auth=1&open_in_app=true") {
            NSWorkspace.shared.open(url)
        }
    }

    private func signInWithGoogle() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authManager.signInWithGoogle()
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showingErrorAlert = true
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    SignInView(authManager: AuthenticationManager())
        .frame(width: 400, height: 650)
}