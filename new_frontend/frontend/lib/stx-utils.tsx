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
    const baseUrl = "https://api.testnet.hiro.so";
    const url = `${baseUrl}/extended/v1/address/${address}/stx`;

    console.log('Fetching STX balance for address:', address);
    console.log('URL:', url);

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'Accept': 'application/json',
      },
    });
    
    if (!response.ok) {
      console.error(`Failed to fetch STX balance: ${response.status} ${response.statusText}`);
      return 0;
    }
    
    const data = await response.json();
    console.log('STX balance response:', data);
    
    if (!data || typeof data.balance === 'undefined') {
      console.error('Invalid response format from STX balance API:', data);
      return 0;
    }
    
    const balance = parseInt(data.balance);
    
    if (isNaN(balance)) {
      console.error('Invalid balance value received from API:', data.balance);
      return 0;
    }
    
    console.log('Successfully fetched STX balance:', balance);
    return balance;
  } catch (error) {
    console.error('Error fetching STX balance:', error);
    console.warn('STX balance warning: Could not fetch current balance, showing 0 as fallback');
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