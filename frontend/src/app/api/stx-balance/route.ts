import { NextRequest, NextResponse } from 'next/server';

// Simple in-memory cache to reduce API calls
const cache = new Map<string, { balance: string; timestamp: number }>();
const CACHE_DURATION = 30000; // 30 seconds

// Helper function to add delay
function delay(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Retry function with exponential backoff
async function retryFetch(url: string, options: RequestInit, maxRetries = 3): Promise<Response> {
  for (let i = 0; i < maxRetries; i++) {
    try {
      const response = await fetch(url, options);
      if (response.status === 429) {
        // Rate limited, wait and retry
        const waitTime = Math.pow(2, i) * 1000; // Exponential backoff: 1s, 2s, 4s
        console.log(`Rate limited, waiting ${waitTime}ms before retry ${i + 1}/${maxRetries}`);
        await delay(waitTime);
        continue;
      }
      return response;
    } catch (error) {
      if (i === maxRetries - 1) throw error;
      await delay(Math.pow(2, i) * 1000);
    }
  }
  throw new Error('Max retries exceeded');
}

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const address = searchParams.get('address');

  if (!address) {
    return NextResponse.json({ error: 'Address parameter is required' }, { status: 400 });
  }

  // Check cache first
  const cached = cache.get(address);
  if (cached && Date.now() - cached.timestamp < CACHE_DURATION) {
    console.log('Returning cached balance for:', address);
    return NextResponse.json({ balance: cached.balance });
  }

  try {
    const baseUrl = "https://api.testnet.hiro.so";
    const url = `${baseUrl}/extended/v1/address/${address}/stx`;

    console.log('Fetching STX balance for address:', address);
    console.log('API URL:', url);

    const response = await retryFetch(url, {
      method: 'GET',
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'TicTacToe-App/1.0',
      },
    });

    if (!response.ok) {
      console.error(`HTTP error! status: ${response.status}, statusText: ${response.statusText}`);
      
      // For rate limiting or server errors, return a fallback
      if (response.status === 429 || response.status >= 500) {
        console.log('API unavailable, returning fallback balance of 0');
        return NextResponse.json({ balance: '0' });
      }
      
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    const data = await response.json();
    console.log('STX balance response:', data);
    
    const balance = data.balance || '0';
    
    // Cache the result
    cache.set(address, { balance, timestamp: Date.now() });
    
    return NextResponse.json({ balance });
  } catch (error: any) {
    console.error('Error fetching STX balance:', error);
    
    // Return fallback balance instead of error to prevent app crash
    return NextResponse.json({ 
      balance: '0',
      warning: 'Could not fetch current balance, showing 0 as fallback'
    });
  }
}
