import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14.21.0'
import { create, verify, getNumericDate } from "https://deno.land/x/djwt@v3.0.1/mod.ts"

// Types
interface VerifyLicenseRequest {
  action: 'verify_license'
}

interface LicenseResponse {
  tier: string
  expiresAt: string
  isTrial: boolean
  trialEndsAt?: string
  signedJWT: string
}

interface UserProfile {
  id: string
  stripe_customer_id?: string
  subscription_tier?: string
  subscription_status?: string
  trial_ends_at?: string
  subscription_expires_at?: string
}

// Initialize clients
const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
)

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-06-20',
})

// JWT signing key (you should generate this and keep it secure)
const JWT_SECRET = Deno.env.get('JWT_SECRET') ?? 'your-jwt-secret-key'

serve(async (req) => {
  // CORS headers
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  }

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get the authorization header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return new Response(
        JSON.stringify({ error: 'Missing or invalid authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const token = authHeader.split(' ')[1]
    
    // Verify the JWT token with Supabase
    const { data: { user }, error: authError } = await supabase.auth.getUser(token)
    
    if (authError || !user) {
      console.error('Auth error:', authError)
      return new Response(
        JSON.stringify({ error: 'Invalid token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Processing license verification for user: ${user.id}`)

    // Get user profile with subscription info
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', user.id)
      .single()

    if (profileError) {
      console.error('Profile error:', profileError)
      return new Response(
        JSON.stringify({ error: 'User profile not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const userProfile = profile as UserProfile
    
    // Determine subscription tier and status
    const licenseInfo = await determineLicenseInfo(userProfile)
    
    // Create signed JWT
    const signedJWT = await createSignedJWT(user, licenseInfo)
    
    const response: LicenseResponse = {
      tier: licenseInfo.tier,
      expiresAt: licenseInfo.expiresAt.toISOString(),
      isTrial: licenseInfo.isTrial,
      trialEndsAt: licenseInfo.trialEndsAt?.toISOString(),
      signedJWT
    }

    console.log(`License verified for user ${user.id}: tier=${licenseInfo.tier}, isTrial=${licenseInfo.isTrial}`)

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

// Helper function to determine license info
async function determineLicenseInfo(profile: UserProfile) {
  const now = new Date()
  
  // Check if user has a Stripe customer ID
  if (!profile.stripe_customer_id) {
    // New user - start 7-day trial
    const trialEnd = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000) // 7 days
    
    // Update profile with trial info
    await supabase
      .from('profiles')
      .update({ 
        subscription_tier: 'stream',
        subscription_status: 'trialing',
        trial_ends_at: trialEnd.toISOString()
      })
      .eq('id', profile.id)
    
    return {
      tier: 'stream',
      isTrial: true,
      trialEndsAt: trialEnd,
      expiresAt: trialEnd
    }
  }

  // User has Stripe customer - check subscription status
  try {
    const subscriptions = await stripe.subscriptions.list({
      customer: profile.stripe_customer_id,
      status: 'all',
      limit: 1
    })

    if (subscriptions.data.length === 0) {
      // No subscription found - check if trial is still valid
      if (profile.trial_ends_at) {
        const trialEnd = new Date(profile.trial_ends_at)
        if (now < trialEnd) {
          return {
            tier: 'stream',
            isTrial: true,
            trialEndsAt: trialEnd,
            expiresAt: trialEnd
          }
        }
      }
      
      // Trial expired, no subscription
      return {
        tier: 'stream',
        isTrial: false,
        expiresAt: new Date(now.getTime() - 1000) // Expired
      }
    }

    const subscription = subscriptions.data[0]
    const subscriptionEnd = new Date(subscription.current_period_end * 1000)
    
    // Determine tier based on subscription
    const tier = mapStripePriceToTier(subscription.items.data[0]?.price?.id || '')
    
    // Update profile with current subscription info
    await supabase
      .from('profiles')
      .update({
        subscription_tier: tier,
        subscription_status: subscription.status,
        subscription_expires_at: subscriptionEnd.toISOString()
      })
      .eq('id', profile.id)

    const isActive = ['active', 'trialing'].includes(subscription.status)
    
    return {
      tier: isActive ? tier : 'stream',
      isTrial: subscription.status === 'trialing',
      trialEndsAt: subscription.status === 'trialing' ? subscriptionEnd : undefined,
      expiresAt: subscriptionEnd
    }

  } catch (stripeError) {
    console.error('Stripe error:', stripeError)
    
    // Fallback to cached profile data
    if (profile.subscription_expires_at) {
      const expiresAt = new Date(profile.subscription_expires_at)
      return {
        tier: profile.subscription_tier || 'stream',
        isTrial: profile.subscription_status === 'trialing',
        trialEndsAt: profile.trial_ends_at ? new Date(profile.trial_ends_at) : undefined,
        expiresAt
      }
    }
    
    // No cached data, return expired
    return {
      tier: 'stream',
      isTrial: false,
      expiresAt: new Date(now.getTime() - 1000)
    }
  }
}

// Map Stripe price IDs to Vistaview tiers
function mapStripePriceToTier(priceId: string): string {
  const priceToTierMap: Record<string, string> = {
    // Replace these with your actual Stripe price IDs
    'price_1ABC123StreamMonthly': 'stream',
    'price_1DEF456LiveMonthly': 'live', 
    'price_1GHI789StageMonthly': 'stage',
    'price_1JKL012ProMonthly': 'pro'
  }
  
  return priceToTierMap[priceId] || 'stream'
}

// Create signed JWT with license claims
async function createSignedJWT(user: any, licenseInfo: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const expiresIn = 24 * 60 * 60 // 24 hours
  
  const payload = {
    iss: 'vistaview.app',
    aud: 'vistaview-app',
    sub: user.id,
    iat: now,
    exp: now + expiresIn,
    tier: licenseInfo.tier,
    trial: licenseInfo.isTrial
  }

  // Create HMAC key from secret
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(JWT_SECRET),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  )

  return await create({ alg: 'HS256', typ: 'JWT' }, payload, key)
}