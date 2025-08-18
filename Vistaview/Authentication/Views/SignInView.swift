//
//  SignInView.swift
//  Vistaview
//
//  Created by Vistaview on 12/19/24.
//

import SwiftUI

struct SignInView: View {
    @ObservedObject var authManager: AuthenticationManager
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUpMode = false
    @State private var showingForgotPassword = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Logo and title
            VStack(spacing: 16) {
                Image(systemName: "tv.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                
                Text("Vistaview")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text(isSignUpMode ? "Create your account" : "Sign in to your account")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            // Form
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.headline)
                    
                    TextField("Enter your email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.headline)
                    
                    SecureField("Enter your password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                
                if let error = authManager.authError {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }
            }
            
            // Actions
            VStack(spacing: 12) {
                Button(action: handlePrimaryAction) {
                    HStack {
                        if authManager.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                        
                        Text(isSignUpMode ? "Create Account" : "Sign In")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(authManager.isLoading || email.isEmpty || password.isEmpty)
                
                HStack {
                    Text(isSignUpMode ? "Already have an account?" : "Don't have an account?")
                        .foregroundColor(.secondary)
                    
                    Button(isSignUpMode ? "Sign In" : "Sign Up") {
                        isSignUpMode.toggle()
                        authManager.authError = nil
                    }
                    .foregroundColor(.accentColor)
                }
                
                if !isSignUpMode {
                    Button("Forgot Password?") {
                        showingForgotPassword = true
                    }
                    .foregroundColor(.secondary)
                    .font(.caption)
                }
            }
            
            Spacer()
            
            // Configuration warning for development
            if !SupabaseConfig.isConfigured {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    
                    Text("Supabase not configured")
                        .font(.headline)
                        .foregroundColor(.orange)
                    
                    Text("Please update SupabaseConfig.swift with your project credentials")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    #if DEBUG
                    if authManager.debugMode {
                        VStack(spacing: 4) {
                            Text("Debug Mode Enabled")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            
                            Text("You can sign in with any email/password for testing")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        .padding(.top, 8)
                    }
                    #endif
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(40)
        .frame(maxWidth: 400)
        .sheet(isPresented: $showingForgotPassword) {
            ForgotPasswordView()
        }
    }
    
    private func handlePrimaryAction() {
        Task {
            if isSignUpMode {
                await authManager.signUp(email: email, password: password)
            } else {
                await authManager.signIn(email: email, password: password)
            }
        }
    }
}

struct ForgotPasswordView: View {
    @State private var email = ""
    @State private var isLoading = false
    @State private var showingSuccess = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            // Header with close button
            HStack {
                Text("Reset Password")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }
            
            VStack(spacing: 16) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                
                Text("Enter your email address and we'll send you a link to reset your password.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.headline)
                
                TextField("Enter your email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }
            
            Button("Send Reset Link") {
                sendResetLink()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(email.isEmpty ? Color.gray : Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(12)
            .disabled(email.isEmpty || isLoading)
            
            Spacer()
        }
        .padding()
        .frame(width: 400, height: 300)
        .alert("Check Your Email", isPresented: $showingSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("We've sent a password reset link to \(email). Please check your email and follow the instructions.")
        }
    }
    
    private func sendResetLink() {
        isLoading = true
        
        // TODO: Implement password reset API call
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isLoading = false
            showingSuccess = true
        }
    }
}

#Preview {
    SignInView(authManager: AuthenticationManager())
}