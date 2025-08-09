import { createNewGame, joinGame, Move, play } from "@/lib/contract";
import { getStxBalance } from "@/lib/stx-utils";
import {
  AppConfig,
  openContractCall,
  showConnect,
  type UserData,
  UserSession,
} from "@stacks/connect";
import { STACKS_TESTNET } from "@stacks/network";
import { PostConditionMode } from "@stacks/transactions";
import { useEffect, useState } from "react";

const appDetails = {
  name: "Tic Tac Toe",
  icon: "https://cryptologos.cc/logos/stacks-stx-logo.png",
};

const appConfig = new AppConfig(["store_write"]);
const userSession = new UserSession({ appConfig });

export function useStacks() {
  const [userData, setUserData] = useState<UserData | null>(null);
  const [stxBalance, setStxBalance] = useState(0);
  const [balanceLoading, setBalanceLoading] = useState(false);

  function connectWallet() {
    console.log("connectWallet called");
    console.log("Available providers:", {
      StacksProvider: !!(window as any).StacksProvider,
      XverseProviders: !!(window as any).XverseProviders,
      LeatherProvider: !!(window as any).LeatherProvider
    });
    
    showConnect({
      appDetails,
      onFinish: () => {
        console.log("Wallet connection finished");
        window.location.reload();
      },
      onCancel: () => {
        console.log("Wallet connection cancelled");
      },
      userSession,
    });
  }

  function disconnectWallet() {
    userSession.signUserOut();
    setUserData(null);
  }

  async function handleCreateGame(
    betAmount: number,
    moveIndex: number,
    move: Move
  ) {
    console.log("handleCreateGame called with:", { betAmount, moveIndex, move });
    
    if (typeof window === "undefined") {
      console.log("Window is undefined - SSR context");
      return;
    }
    
    if (moveIndex < 0 || moveIndex > 8) {
      console.log("Invalid move index:", moveIndex);
      window.alert("Invalid move. Please make a valid move.");
      return;
    }
    
    if (betAmount <= 0) {
      console.log("Invalid bet amount:", betAmount);
      window.alert("Please make a bet");
      return;
    }

    try {
      if (!userData) {
        console.log("User not connected");
        throw new Error("User not connected");
      }
      
      console.log("User data:", userData);
      console.log("User session is signed in:", userSession.isUserSignedIn());
      
      // Check if we have access to the Stacks wallet
      console.log("Window StacksProvider:", (window as any).StacksProvider);
      console.log("Available wallet providers:", Object.keys(window).filter(key => key.toLowerCase().includes('stacks') || key.toLowerCase().includes('wallet')));
      
      // Check for various wallet providers
      const hasHiroWallet = !!(window as any).StacksProvider;
      const hasXverseWallet = !!(window as any).XverseProviders;
      const hasLeatherWallet = !!(window as any).LeatherProvider;
      
      console.log("Wallet detection:", { hasHiroWallet, hasXverseWallet, hasLeatherWallet });
      
      if (!hasHiroWallet && !hasXverseWallet && !hasLeatherWallet) {
        console.warn("No Stacks wallet provider detected");
        window.alert("No Stacks wallet detected. Please install a Stacks wallet extension (like Hiro Wallet, Xverse, or Leather) and try again.");
        return;
      }
      
      console.log("Creating transaction options...");
      const txOptions = await createNewGame(betAmount, moveIndex, move);
      console.log("Transaction options created:", txOptions);
      
      console.log("Opening contract call...");
      console.log("About to call openContractCall with userSession:", !!userSession);
      
      try {
        const result = await openContractCall({
          ...txOptions,
          appDetails,
          onFinish: (data) => {
            console.log("Transaction finished:", data);
            if (data.txId) {
              console.log("Transaction ID:", data.txId);
              window.alert(`Transaction submitted! TX ID: ${data.txId}`);
            } else {
              window.alert("Transaction was signed but may have failed");
            }
          },
          onCancel: () => {
            console.log("Transaction was cancelled by user");
            window.alert("Transaction cancelled");
          },
          postConditionMode: PostConditionMode.Allow,
          userSession,
          network: STACKS_TESTNET,
        });
        
        console.log("openContractCall result:", result);
        console.log("Contract call opened successfully");
      } catch (contractCallError) {
        console.error("Error in openContractCall:", contractCallError);
        window.alert(`Failed to open wallet: ${contractCallError}`);
        throw contractCallError;
      }
    } catch (_err) {
      const err = _err as Error;
      console.error("Error in handleCreateGame:", err);
      window.alert(err.message);
    }
  }

  async function handleJoinGame(gameId: number, moveIndex: number, move: Move) {
    if (typeof window === "undefined") return;
    if (moveIndex < 0 || moveIndex > 8) {
      window.alert("Invalid move. Please make a valid move.");
      return;
    }

    try {
      if (!userData) throw new Error("User not connected");
      const txOptions = await joinGame(gameId, moveIndex, move);
      await openContractCall({
        ...txOptions,
        appDetails,
        onFinish: (data) => {
          console.log(data);
          if (data.txId) {
            console.log("Join game transaction ID:", data.txId);
            window.alert(`Join game transaction submitted! TX ID: ${data.txId}`);
          } else {
            window.alert("Join game transaction was signed but may have failed");
          }
        },
        onCancel: () => {
          console.log("Join game transaction was cancelled by user");
          window.alert("Join game transaction cancelled");
        },
        postConditionMode: PostConditionMode.Allow,
        userSession,
        network: STACKS_TESTNET,
      });
    } catch (_err) {
      const err = _err as Error;
      console.error(err);
      window.alert(err.message);
    }
  }

  async function handlePlayGame(gameId: number, moveIndex: number, move: Move) {
    if (typeof window === "undefined") return;
    if (moveIndex < 0 || moveIndex > 8) {
      window.alert("Invalid move. Please make a valid move.");
      return;
    }

    try {
      if (!userData) throw new Error("User not connected");
      const txOptions = await play(gameId, moveIndex, move);
      await openContractCall({
        ...txOptions,
        appDetails,
        onFinish: (data) => {
          console.log(data);
          if (data.txId) {
            console.log("Play game transaction ID:", data.txId);
            window.alert(`Play game transaction submitted! TX ID: ${data.txId}`);
          } else {
            window.alert("Play game transaction was signed but may have failed");
          }
        },
        onCancel: () => {
          console.log("Play game transaction was cancelled by user");
          window.alert("Play game transaction cancelled");
        },
        postConditionMode: PostConditionMode.Allow,
        userSession,
        network: STACKS_TESTNET,
      });
    } catch (_err) {
      const err = _err as Error;
      console.error(err);
      window.alert(err.message);
    }
  }

  useEffect(() => {
    if (userSession.isSignInPending()) {
      userSession.handlePendingSignIn().then((userData) => {
        setUserData(userData);
      });
    } else if (userSession.isUserSignedIn()) {
      setUserData(userSession.loadUserData());
    }
  }, []);

  useEffect(() => {
    if (userData) {
      const address = userData.profile.stxAddress.testnet;
      setBalanceLoading(true);
      getStxBalance(address)
        .then((balance) => {
          setStxBalance(balance);
        })
        .catch((error) => {
          console.error('Failed to fetch STX balance:', error);
          setStxBalance(0); // Set to 0 as fallback
        })
        .finally(() => {
          setBalanceLoading(false);
        });
    }
  }, [userData]);

  return {
    userData,
    stxBalance,
    balanceLoading,
    connectWallet,
    disconnectWallet,
    handleCreateGame,
    handleJoinGame,
    handlePlayGame,
  };
}