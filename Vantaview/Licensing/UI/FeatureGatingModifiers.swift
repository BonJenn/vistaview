//
//  FeatureGatingModifiers.swift
//  Vistaview
//
//  Created by Vistaview on 12/19/24.
//

import SwiftUI

// MARK: - Feature Gating View Modifier

struct FeatureGatingModifier: ViewModifier {
    let feature: FeatureKey
    @ObservedObject var licenseManager: LicenseManager
    @State private var showPaywall = false
    @State private var isFeatureEnabled = false
    
    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(isFeatureEnabled ? 1.0 : 0.3)
                .disabled(!isFeatureEnabled)
            
            if !isFeatureEnabled {
                FeatureLockedOverlay(
                    feature: feature,
                    requiredTier: FeatureMatrix.minimumTier(for: feature),
                    currentTier: licenseManager.currentTier
                ) {
                    showPaywall = true
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(
                highlightedFeature: feature,
                licenseManager: licenseManager
            )
        }
        .onAppear {
            updateFeatureState()
        }
        .onChange(of: licenseManager.currentTier) { _, _ in
            updateFeatureState()
        }
        .onChange(of: licenseManager.status) { _, _ in
            updateFeatureState()
        }
    }
    
    private func updateFeatureState() {
        Task { @MainActor in
            isFeatureEnabled = licenseManager.isEnabled(feature)
        }
    }
}

// MARK: - Feature Locked Overlay

struct FeatureLockedOverlay: View {
    let feature: FeatureKey
    let requiredTier: PlanTier
    let currentTier: PlanTier?
    let onUpgradeTapped: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundColor(.secondary)
            
            VStack(spacing: 4) {
                Text(feature.displayName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                Text("Requires \(requiredTier.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button("Upgrade") {
                onUpgradeTapped()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - License Status Banner

struct LicenseStatusBanner: View {
    @ObservedObject var licenseManager: LicenseManager
    @State private var showPaywall = false
    
    var body: some View {
        Group {
            if licenseManager.status.needsAttention {
                HStack {
                    statusIcon
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(licenseManager.status.displayText)
                            .font(.headline)
                        
                        if let suggestion = statusSuggestion {
                            Text(suggestion)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button(actionButtonTitle) {
                        handleActionButton()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .background(bannerColor.opacity(0.1))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(bannerColor),
                    alignment: .bottom
                )
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(licenseManager: licenseManager)
        }
    }
    
    private var statusIcon: some View {
        Group {
            switch licenseManager.status {
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
            default:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .font(.title2)
    }
    
    private var bannerColor: Color {
        switch licenseManager.status {
        case .trial, .grace:
            return .orange
        case .expired, .error:
            return .red
        default:
            return .green
        }
    }
    
    private var statusSuggestion: String? {
        switch licenseManager.status {
        case .trial(let days) where days <= 3:
            return "Upgrade to continue using Vistaview after your trial"
        case .grace:
            return "Reconnect to the internet to verify your subscription"
        case .expired:
            return "Renew your subscription to continue using Vistaview"
        case .error:
            return "Check your internet connection"
        default:
            return nil
        }
    }
    
    private var actionButtonTitle: String {
        switch licenseManager.status {
        case .trial, .expired:
            return "Upgrade"
        case .grace, .error:
            return "Retry"
        default:
            return "Manage"
        }
    }
    
    private func handleActionButton() {
        switch licenseManager.status {
        case .trial, .expired:
            showPaywall = true
        case .grace, .error:
            Task {
                await licenseManager.refreshLicense(sessionToken: nil) // TODO: Get actual session token
            }
        default:
            showPaywall = true
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Gate this view behind a feature requirement
    func gated(_ feature: FeatureKey, licenseManager: LicenseManager) -> some View {
        modifier(FeatureGatingModifier(feature: feature, licenseManager: licenseManager))
    }
}

// MARK: - Utility Functions for MainActor Context

/// Check if a feature is enabled (for imperative usage in MainActor context)
@MainActor
func require(_ feature: FeatureKey, licenseManager: LicenseManager) -> Bool {
    return licenseManager.isEnabled(feature)
}