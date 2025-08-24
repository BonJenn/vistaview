//
//  PaywallView.swift
//  Vantaview
//
//  Created by Vantaview on 12/19/24.
//

import SwiftUI

struct PaywallView: View {
    let highlightedFeature: FeatureKey?
    @ObservedObject var licenseManager: LicenseManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTier: PlanTier = .live
    
    init(highlightedFeature: FeatureKey? = nil, licenseManager: LicenseManager) {
        self.highlightedFeature = highlightedFeature
        self.licenseManager = licenseManager
        
        // Set initial selected tier based on highlighted feature
        if let feature = highlightedFeature {
            self._selectedTier = State(initialValue: FeatureMatrix.minimumTier(for: feature))
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("Upgrade Vantaview")
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    
                    tierComparisonSection
                    
                    featuresMatrixSection
                    
                    trialInfoSection
                    
                    ctaSection
                }
                .padding()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            if let feature = highlightedFeature {
                VStack(spacing: 8) {
                    Image(systemName: "lock.open")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    
                    Text("Unlock \(feature.displayName)")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(feature.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "star.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    
                    Text("Unlock Your Creative Potential")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Choose the perfect plan for your live production needs")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
    
    private var tierComparisonSection: some View {
        VStack(spacing: 16) {
            HStack {
                ForEach(PlanTier.allCases, id: \.self) { tier in
                    TierCard(
                        tier: tier,
                        isSelected: selectedTier == tier,
                        isCurrent: licenseManager.currentTier == tier,
                        isHighlighted: highlightedFeature != nil && FeatureMatrix.minimumTier(for: highlightedFeature!) == tier
                    ) {
                        selectedTier = tier
                    }
                }
            }
        }
    }
    
    private var featuresMatrixSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Feature Comparison")
                .font(.title2)
                .fontWeight(.semibold)
            
            FeatureMatrixTable(
                selectedTier: selectedTier,
                highlightedFeature: highlightedFeature
            )
        }
    }
    
    private var trialInfoSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.orange)
                Text("7-Day Free Trial")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            Text("Start your free trial today. No credit card required. Cancel anytime.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var ctaSection: some View {
        VStack(spacing: 16) {
            Button(action: handleUpgrade) {
                HStack {
                    if licenseManager.currentTier == nil {
                        Text("Start Free Trial")
                    } else if let current = licenseManager.currentTier,
                              selectedTier.rawValue > current.rawValue {
                        Text("Upgrade to \(selectedTier.displayName)")
                    } else {
                        Text("Manage Billing")
                    }
                    
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button("Manage Billing") {
                openBillingPortal()
            }
            .foregroundColor(.secondary)
        }
    }
    
    private func handleUpgrade() {
        // TODO: Implement upgrade flow
        // This would typically open the web billing portal or handle in-app purchase
        openBillingPortal()
    }
    
    private func openBillingPortal() {
        NSWorkspace.shared.open(LicenseConstants.billingPortalURL)
        dismiss()
    }
}

// MARK: - Tier Card

struct TierCard: View {
    let tier: PlanTier
    let isSelected: Bool
    let isCurrent: Bool
    let isHighlighted: Bool
    let onSelect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tier.displayName)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if isCurrent {
                        Text("CURRENT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                }
                
                Text("$\(tier.monthlyPrice)/month")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
                
                Text(tier.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 6) {
                let features = Array(FeatureMatrix.features(for: tier).prefix(3))
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        
                        Text(feature.displayName)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                
                if FeatureMatrix.features(for: tier).count > 3 {
                    Text("+ \(FeatureMatrix.features(for: tier).count - 3) more features")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isHighlighted ? Color.orange :
                            isSelected ? Color.accentColor :
                            isCurrent ? Color.green :
                            Color.clear,
                            lineWidth: isHighlighted || isSelected || isCurrent ? 2 : 0
                        )
                )
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Feature Matrix Table

struct FeatureMatrixTable: View {
    let selectedTier: PlanTier
    let highlightedFeature: FeatureKey?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Feature")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                ForEach(PlanTier.allCases, id: \.self) { tier in
                    Text(tier.displayName)
                        .font(.headline)
                        .frame(width: 80)
                        .foregroundColor(tier == selectedTier ? .accentColor : .primary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Features
            ForEach(FeatureKey.allCases, id: \.self) { feature in
                FeatureRow(
                    feature: feature,
                    selectedTier: selectedTier,
                    isHighlighted: highlightedFeature == feature
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor))
        )
    }
}

struct FeatureRow: View {
    let feature: FeatureKey
    let selectedTier: PlanTier
    let isHighlighted: Bool
    
    var body: some View {
        HStack {
            Text(feature.displayName)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(isHighlighted ? .orange : .primary)
                .fontWeight(isHighlighted ? .semibold : .regular)
            
            ForEach(PlanTier.allCases, id: \.self) { tier in
                Group {
                    if FeatureMatrix.isEnabled(feature, for: tier) {
                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                            .fontWeight(.semibold)
                    } else {
                        Image(systemName: "minus")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 80)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            isHighlighted ? Color.orange.opacity(0.1) : Color.clear
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
}