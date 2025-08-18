// Test script to verify license verification endpoint
const SUPABASE_URL = 'https://your-project.supabase.co'
const TEST_TOKEN = 'your-test-session-token'

async function testLicenseVerification() {
  try {
    const response = await fetch(`${SUPABASE_URL}/functions/v1/verify-license`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${TEST_TOKEN}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ action: 'verify_license' })
    })

    const result = await response.json()
    console.log('License verification result:', result)
    
    if (response.ok) {
      console.log('✅ License verification successful')
      console.log(`Tier: ${result.tier}`)
      console.log(`Trial: ${result.isTrial}`)
      console.log(`Expires: ${result.expiresAt}`)
    } else {
      console.log('❌ License verification failed:', result.error)
    }
  } catch (error) {
    console.error('❌ Test failed:', error)
  }
}

testLicenseVerification()