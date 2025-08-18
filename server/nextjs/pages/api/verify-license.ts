import { NextApiRequest, NextApiResponse } from 'next'
import { createClient } from '@supabase/supabase-js'
import Stripe from 'stripe'
import jwt from 'jsonwebtoken'

const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: '2024-06-20',
})

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' })
  }

  const authHeader = req.headers.authorization
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing authorization header' })
  }

  const token = authHeader.split(' ')[1]

  try {
    // Verify token with Supabase
    const { data: { user }, error } = await supabase.auth.getUser(token)
    
    if (error || !user) {
      return res.status(401).json({ error: 'Invalid token' })
    }

    // Get user profile
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', user.id)
      .single()

    if (profileError) {
      return res.status(404).json({ error: 'User profile not found' })
    }

    // Determine license info (same logic as Edge Function)
    const licenseInfo = await determineLicenseInfo(profile)
    
    // Create signed JWT
    const signedJWT = jwt.sign(
      {
        iss: 'vistaview.app',
        aud: 'vistaview-app',
        sub: user.id,
        tier: licenseInfo.tier,
        trial: licenseInfo.isTrial
      },
      process.env.JWT_SECRET!,
      { expiresIn: '24h' }
    )

    res.json({
      tier: licenseInfo.tier,
      expiresAt: licenseInfo.expiresAt.toISOString(),
      isTrial: licenseInfo.isTrial,
      trialEndsAt: licenseInfo.trialEndsAt?.toISOString(),
      signedJWT
    })

  } catch (error) {
    console.error('License verification error:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
}

// Include the same helper functions from the Edge Function