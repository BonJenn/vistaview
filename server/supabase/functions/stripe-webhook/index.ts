import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14.21.0'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-06-20',
})

const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
)

const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET') ?? ''

serve(async (req) => {
  const signature = req.headers.get('stripe-signature')
  
  if (!signature || !webhookSecret) {
    return new Response('Missing signature or webhook secret', { status: 400 })
  }

  try {
    const body = await req.text()
    const event = stripe.webhooks.constructEvent(body, signature, webhookSecret)
    
    console.log(`Processing Stripe webhook: ${event.type}`)

    switch (event.type) {
      case 'customer.subscription.created':
      case 'customer.subscription.updated':
      case 'customer.subscription.deleted':
        await handleSubscriptionEvent(event.data.object as Stripe.Subscription)
        break
        
      case 'customer.created':
        await handleCustomerCreated(event.data.object as Stripe.Customer)
        break
        
      case 'invoice.payment_succeeded':
        await handlePaymentSucceeded(event.data.object as Stripe.Invoice)
        break
        
      case 'invoice.payment_failed':
        await handlePaymentFailed(event.data.object as Stripe.Invoice)
        break
        
      default:
        console.log(`Unhandled event type: ${event.type}`)
    }

    return new Response(JSON.stringify({ received: true }), {
      headers: { 'Content-Type': 'application/json' }
    })

  } catch (error) {
    console.error('Webhook error:', error)
    return new Response(`Webhook error: ${error.message}`, { status: 400 })
  }
})

async function handleSubscriptionEvent(subscription: Stripe.Subscription) {
  const customerId = subscription.customer as string
  const tier = mapStripePriceToTier(subscription.items.data[0]?.price?.id || '')
  const expiresAt = new Date(subscription.current_period_end * 1000)
  
  // Update profile with subscription info
  const { error } = await supabase
    .from('profiles')
    .update({
      subscription_tier: tier,
      subscription_status: subscription.status,
      subscription_expires_at: expiresAt.toISOString(),
      updated_at: new Date().toISOString()
    })
    .eq('stripe_customer_id', customerId)
    
  if (error) {
    console.error('Error updating subscription:', error)
  } else {
    console.log(`Updated subscription for customer ${customerId}: ${tier} (${subscription.status})`)
  }
}

async function handleCustomerCreated(customer: Stripe.Customer) {
  if (!customer.email) return
  
  // Link Stripe customer to Supabase user
  const { error } = await supabase
    .from('profiles')
    .update({ stripe_customer_id: customer.id })
    .eq('email', customer.email)
    
  if (error) {
    console.error('Error linking customer:', error)
  } else {
    console.log(`Linked customer ${customer.id} to user ${customer.email}`)
  }
}

async function handlePaymentSucceeded(invoice: Stripe.Invoice) {
  // Payment succeeded - subscription should be active
  console.log(`Payment succeeded for customer ${invoice.customer}`)
}

async function handlePaymentFailed(invoice: Stripe.Invoice) {
  // Payment failed - might need to handle grace period
  console.log(`Payment failed for customer ${invoice.customer}`)
}

function mapStripePriceToTier(priceId: string): string {
  const priceToTierMap: Record<string, string> = {
    'price_stream_monthly': 'stream',
    'price_live_monthly': 'live',
    'price_stage_monthly': 'stage', 
    'price_pro_monthly': 'pro',
    'price_stream_yearly': 'stream',
    'price_live_yearly': 'live',
    'price_stage_yearly': 'stage',
    'price_pro_yearly': 'pro'
  }
  
  return priceToTierMap[priceId] || 'stream'
}