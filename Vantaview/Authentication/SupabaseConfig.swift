//
//  SupabaseConfig.swift
//  Vantaview
//
//  Created by Vantaview on 12/19/24.
//

import Foundation

/// Configuration for Supabase integration
struct SupabaseConfig {
    
    /// Your Supabase project URL (get this from dashboard)
    static let projectURL = URL(string: "https://iaxqbatmntobejiwtbqx.supabase.co")!
    
    /// Your Supabase anon key (paste the real key here)
    static let anonKey = "paste-your-eyJ...-key-here"
    
    /// License verification endpoint
    static let licenseVerificationURL = projectURL.appendingPathComponent("functions/v1/verify-license")
    
    // MARK: - Validation
    
    static var isConfigured: Bool {
        return !anonKey.contains("placeholder") && !anonKey.contains("your-actual")
    }
}