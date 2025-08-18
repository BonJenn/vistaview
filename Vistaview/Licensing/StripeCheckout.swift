//
//  StripeCheckout.swift
//  Vistaview
//
//  Created by Vistaview on 12/19/24.
//

import Foundation

class StripeCheckout {
    
    static func createCheckoutURL(for tier: PlanTier, userID: String) -> URL? {
        // Map tiers to your actual Stripe price IDs
        let priceID: String
        switch tier {
        case .stream: priceID = "price_1ABC123StreamMonthly"
        case .live: priceID = "price_1DEF456LiveMonthly"
        case .stage: priceID = "price_1GHI789StageMonthly"
        case .pro: priceID = "price_1JKL012ProMonthly"
        }
        
        // Create Stripe Checkout URL
        var components = URLComponents(string: "https://checkout.stripe.com/pay")!
        components.queryItems = [
            URLQueryItem(name: "price", value: priceID),
            URLQueryItem(name: "success_url", value: "vistaview://checkout/success"),
            URLQueryItem(name: "cancel_url", value: "vistaview://checkout/cancel"),
            URLQueryItem(name: "client_reference_id", value: userID)
        ]
        
        return components.url
    }
}