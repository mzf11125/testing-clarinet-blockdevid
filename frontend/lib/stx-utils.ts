export function abbreviateAddress(address: string) {
  return `${address.substring(0, 5)}...${address.substring(36)}`;
}

export function abbreviateTxnId(txnId: string) {
  return `${txnId.substring(0, 5)}...${txnId.substring(62)}`;
}

export function explorerAddress(address: string) {
  return `https://explorer.hiro.so/address/${address}?chain=testnet`;
}

export async function getStxBalance(address: string) {
  try {
    const url = `/api/stx-balance?address=${encodeURIComponent(address)}`;

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'Accept': 'application/json',
      },
    });

    if (!response.ok) {
      console.warn(`STX balance API returned status ${response.status}, using fallback balance`);
      return 0;
    }

    const data = await response.json();
    
    // Check for warning (API fallback)
    if (data.warning) {
      console.warn('STX balance warning:', data.warning);
    }
    
    // Even if there's an error field, try to use the balance if provided
    const balance = parseInt(data.balance) || 0;
    return balance;
  } catch (error) {
    console.error('Error fetching STX balance:', error);
    // Return 0 as fallback balance - don't throw error to prevent app crash
    return 0;
  }
}

// Convert a raw STX amount to a human readable format by respecting the 6 decimal places
export function formatStx(amount: number) {
  return parseFloat((amount / 10 ** 6).toFixed(2));
}

// Convert a human readable STX balance to the raw amount
export function parseStx(amount: number) {
  return amount * 10 ** 6;
}