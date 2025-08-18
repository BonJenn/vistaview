//
//  AccountView.swift
//  Vistaview
//
//  Created by Vistaview on 12/19/24.
//

import SwiftUI

struct AccountView: View {
    @ObservedObject var licenseManager: LicenseManager
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showPaywall = false
    @State private var isRefreshing = false
    
    var body: some View {
        Form {
            Section("Account") {
                HStack {
                    Text("Vistaview ID")
                    Spacer()
                    Text(authManager.userID ?? "Not available")
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                
                HStack {
                    Text("Email")
                    Spacer()
                    Text(authManager.currentUser?.email ?? "Not available")
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                
                if let user = authManager.currentUser {
                    HStack {
                        Text("Member since")
                        Spacer()
                        Text(user.createdAt, style: .date)
                            .foregroundColor(.secondary)
                    }
                    
                    if !user.emailConfirmed {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Email not confirmed")
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            
            Section("Subscription") {
                subscriptionStatusSection
            }
            
            Section("Actions") {
                actionButtonsSection
            }
            
            #if DEBUG
            Section("Debug") {
                debugSection
            }
            #endif
        }
        .formStyle(.grouped)
        .navigationTitle("Account")
        .sheet(isPresented: $showPaywall) {
            PaywallView(licenseManager: licenseManager)
        }
    }
    
    private var subscriptionStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                statusIcon
                
                VStack(alignment: .leading, spacing: 4) {
                    if let tier = licenseManager.currentTier {
                        Text(tier.displayName)
                            .font(.headline)
                        
                        Text("$\(tier.monthlyPrice)/month")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No Active Subscription")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(licenseManager.status.displayText)
                        .font(.caption)
                        .foregroundColor(statusColor)
                }
                
                Spacer()
            }
            
            if let lastRefresh = licenseManager.lastRefreshDate {
                Text("Last updated: \(lastRefresh, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button(action: refreshLicense) {
                HStack {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh License")
                }
            }
            .disabled(isRefreshing)
            
            Button("Manage Billing") {
                openBillingPortal()
            }
            
            if licenseManager.status == .expired || licenseManager.currentTier == nil {
                Button("Upgrade Now") {
                    showPaywall = true
                }
                .buttonStyle(.borderedProminent)
            }
            
            Button("Sign Out") {
                signOut()
            }
            .foregroundColor(.red)
        }
    }
    
    #if DEBUG
    private var debugSection: some View {
        VStack(spacing: 12) {
            Picker("Debug Tier", selection: $licenseManager.debugImpersonatedTier) {
                Text("None").tag(nil as PlanTier?)
                ForEach(PlanTier.allCases, id: \.self) { tier in
                    Text(tier.displayName).tag(tier as PlanTier?)
                }
            }
            
            Toggle("Offline Mode", isOn: $licenseManager.debugOfflineMode)
            
            Toggle("Expired Mode", isOn: $licenseManager.debugExpiredMode)
            
            Button("Clear Cache") {
                _ = KeychainHelper.clearAllCachedLicenses()
            }
            .foregroundColor(.orange)
        }
    }
    #endif
    
    private var statusIcon: some View {
        Group {
            switch licenseManager.status {
            case .active:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .trial:
                Image(systemName: "clock.fill")
                    .foregroundColor(.orange)
            case .grace:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            case .expired:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            case .error:
                Image(systemName: "wifi.exclamationmark")
                    .foregroundColor(.red)
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.secondary)
            }
        }
        .font(.title2)
    }
    
    private var statusColor: Color {
        switch licenseManager.status {
        case .active:
            return .green
        case .trial, .grace:
            return .orange
        case .expired, .error:
            return .red
        case .unknown:
            return .secondary
        }
    }
    
    private func refreshLicense() {
        guard let sessionToken = authManager.accessToken else {
            return
        }
        
        isRefreshing = true
        Task {
            await licenseManager.refreshLicense(sessionToken: sessionToken, userID: authManager.userID)
            await MainActor.run {
                isRefreshing = false
            }
        }
    }
    
    private func openBillingPortal() {
        NSWorkspace.shared.open(LicenseConstants.billingPortalURL)
    }
    
    private func signOut() {
        Task {
            await authManager.signOut()
        }
    }
}