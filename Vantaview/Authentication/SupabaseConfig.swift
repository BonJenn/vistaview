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
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlheHFiYXRtbnRvYmVqaXd0YnF4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUwMzk0MzcsImV4cCI6MjA3MDYxNTQzN30.AWaDbQCIKFBKxJ_kRoUrn5Nsqq0DvJZBLtF1q44bkek"
    
    /// License verification endpoint
    static let licenseVerificationURL = projectURL.appendingPathComponent("functions/v1/verify-license")
    
    // MARK: - Validation
    
    static var isConfigured: Bool {
        return !anonKey.contains("placeholder") && !anonKey.contains("your-actual") && !anonKey.contains("paste-your")
    }
}