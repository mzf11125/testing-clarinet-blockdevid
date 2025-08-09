import { STACKS_TESTNET } from "@stacks/network";
import {
  BooleanCV,
  cvToValue,
  fetchCallReadOnlyFunction,
  ListCV,
  OptionalCV,
  PrincipalCV,
  TupleCV,
  uintCV,
  UIntCV,
} from "@stacks/transactions";

const CONTRACT_ADDRESS = "ST2TG9G3H0WD4Q69CXZ5KW973RFX5XGHD54TGX5PR";
const CONTRACT_NAME = "tic-tac-toe";
//0xcb6492b5bd17e9d28fe80325b53b9d35cec53925c605b71fac601499fdffe211
type GameCV = {
  "player-one": PrincipalCV;
  "player-two": OptionalCV<PrincipalCV>;
  "is-player-one-turn": BooleanCV;
  "bet-amount": UIntCV;
  board: ListCV<UIntCV>;
  winner: OptionalCV<PrincipalCV>;
};

export type Game = {
  id: number;
  "player-one": string;
  "player-two": string | null;
  "is-player-one-turn": boolean;
  "bet-amount": number;
  board: number[];
  winner: string | null;
};

export enum Move {
  EMPTY = 0,
  X = 1,
  O = 2,
}

export const EMPTY_BOARD = [
  Move.EMPTY,
  Move.EMPTY,
  Move.EMPTY,
  Move.EMPTY,
  Move.EMPTY,
  Move.EMPTY,
  Move.EMPTY,
  Move.EMPTY,
  Move.EMPTY,
];

// Helper function to add delay between API calls
function delay(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Helper function to retry API calls with exponential backoff
async function retryApiCall<T>(fn: () => Promise<T>, maxRetries = 3, baseDelay = 1000): Promise<T> {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn();
    } catch (error: any) {
      if (error.message?.includes('429') || error.message?.includes('rate limit')) {
        const delayTime = baseDelay * Math.pow(2, i); // Exponential backoff
        console.log(`Rate limited, retrying in ${delayTime}ms... (attempt ${i + 1}/${maxRetries})`);
        await delay(delayTime);
        if (i === maxRetries - 1) throw error;
      } else {
        throw error;
      }
    }
  }
  throw new Error('Max retries reached');
}

export async function getAllGames() {
  try {
    // Fetch the latest-game-id from the contract with retry logic
    const latestGameIdCV = await retryApiCall(async () => {
      return (await fetchCallReadOnlyFunction({
        contractAddress: CONTRACT_ADDRESS,
        contractName: CONTRACT_NAME,
        functionName: "get-latest-game-id",
        functionArgs: [],
        senderAddress: CONTRACT_ADDRESS,
        network: STACKS_TESTNET,
      })) as UIntCV;
    });

    // Convert the uintCV to a JS/TS number type
    const latestGameId = parseInt(latestGameIdCV.value.toString());

    // Loop from 0 to latestGameId-1 and fetch the game details for each game
    const games: Game[] = [];
    for (let i = 0; i < latestGameId; i++) {
      try {
        const game = await getGame(i);
        if (game) games.push(game);
        // Add a small delay between requests to avoid rate limiting
        if (i < latestGameId - 1) {
          await delay(200); // 200ms delay between requests
        }
      } catch (error: any) {
        console.error(`Failed to fetch game ${i}:`, error);
        // Continue with next game instead of failing completely
      }
    }
    return games;
  } catch (error: any) {
    console.error('Failed to fetch games:', error);
    // Return empty array instead of throwing to prevent app crash
    return [];
  }
}

export async function getGame(gameId: number) {
  try {
    // Use the get-game read only function to fetch the game details for the given gameId with retry logic
    const gameDetails = await retryApiCall(async () => {
      return await fetchCallReadOnlyFunction({
        contractAddress: CONTRACT_ADDRESS,
        contractName: CONTRACT_NAME,
        functionName: "get-game",
        functionArgs: [uintCV(gameId)],
        senderAddress: CONTRACT_ADDRESS,
        network: STACKS_TESTNET,
      });
    });

    const responseCV = gameDetails as OptionalCV<TupleCV<GameCV>>;
    // If we get back a none, then the game does not exist and we return null
    if (responseCV.type === "none") return null;
    // If we get back a value that is not a tuple, something went wrong and we return null
    if (responseCV.value.type !== "tuple") return null;

    // If we got back a GameCV tuple, we can convert it to a Game object
    const gameCV = responseCV.value.value;

    const game: Game = {
      id: gameId,
      "player-one": gameCV["player-one"].value,
      "player-two":
        gameCV["player-two"].type === "some"
          ? gameCV["player-two"].value.value
          : null,
      "is-player-one-turn": cvToValue(gameCV["is-player-one-turn"]),
      "bet-amount": parseInt(gameCV["bet-amount"].value.toString()),
      board: gameCV["board"].value.map((cell) => parseInt(cell.value.toString())),
      winner:
        gameCV["winner"].type === "some" ? gameCV["winner"].value.value : null,
    };
    return game;
  } catch (error: any) {
    console.error(`Failed to fetch game ${gameId}:`, error);
    return null;
  }
}

export async function createNewGame(
  betAmount: number,
  moveIndex: number,
  move: Move
) {
  const txOptions = {
    contractAddress: CONTRACT_ADDRESS,
    contractName: CONTRACT_NAME,
    functionName: "create-game",
    functionArgs: [uintCV(betAmount), uintCV(moveIndex), uintCV(move)],
  };

  return txOptions;
}

export async function joinGame(gameId: number, moveIndex: number, move: Move) {
  const txOptions = {
    contractAddress: CONTRACT_ADDRESS,
    contractName: CONTRACT_NAME,
    functionName: "join-game",
    functionArgs: [uintCV(gameId), uintCV(moveIndex), uintCV(move)],
  };

  return txOptions;
}

export async function play(gameId: number, moveIndex: number, move: Move) {
  const txOptions = {
    contractAddress: CONTRACT_ADDRESS,
    contractName: CONTRACT_NAME,
    functionName: "play",
    functionArgs: [uintCV(gameId), uintCV(moveIndex), uintCV(move)],
  };

  return txOptions;
}