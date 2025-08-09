import { describe, it, expect } from "vitest";
import { Cl } from "@stacks/transactions";

describe("Tic Tac Toe Game Tests", () => {

  it("Can create new game successfully", () => {
    const accounts = simnet.getAccounts();
    const player1 = accounts.get('wallet_1')!;
    const betAmount = 1000000;
    
    const result = simnet.callPublicFn(
      'tic-tac-toe',
      'create-game', 
      [Cl.uint(betAmount), Cl.uint(0), Cl.uint(1)],
      player1
    );
    
    expect(result.result).toEqual(Cl.ok(Cl.uint(0)));
  });

  it("Player two can join game successfully", () => {
    const accounts = simnet.getAccounts();
    const player1 = accounts.get('wallet_1')!;
    const player2 = accounts.get('wallet_2')!;
    const betAmount = 1000000;
    
    // Create game first
    simnet.callPublicFn(
      'tic-tac-toe',
      'create-game', 
      [Cl.uint(betAmount), Cl.uint(0), Cl.uint(1)],
      player1
    );
    
    // Join game
    const result = simnet.callPublicFn(
      'tic-tac-toe',
      'join-game', 
      [Cl.uint(0), Cl.uint(1), Cl.uint(2)],
      player2
    );
    
    expect(result.result).toEqual(Cl.ok(Cl.uint(0)));
  });

  it("Winner receives complete prize pool", () => {
    const accounts = simnet.getAccounts();
    const player1 = accounts.get('wallet_1')!;
    const player2 = accounts.get('wallet_2')!;
    const betAmount = 1000000;
    const gameId = 0;
    
    // Create and join game
    simnet.callPublicFn('tic-tac-toe', 'create-game', [Cl.uint(betAmount), Cl.uint(0), Cl.uint(1)], player1);
    simnet.callPublicFn('tic-tac-toe', 'join-game', [Cl.uint(gameId), Cl.uint(1), Cl.uint(2)], player2);
    
    // Setup winning game scenario untuk Player 1 (diagonal win: 0, 4, 8)
    simnet.callPublicFn('tic-tac-toe', 'play', [Cl.uint(gameId), Cl.uint(3), Cl.uint(2)], player2);
    simnet.callPublicFn('tic-tac-toe', 'play', [Cl.uint(gameId), Cl.uint(4), Cl.uint(1)], player1);
    simnet.callPublicFn('tic-tac-toe', 'play', [Cl.uint(gameId), Cl.uint(5), Cl.uint(2)], player2);
    
    // Winning move
    const winningMove = simnet.callPublicFn(
      'tic-tac-toe', 
      'play', 
      [Cl.uint(gameId), Cl.uint(8), Cl.uint(1)],
      player1
    );
    expect(winningMove.result).toEqual(Cl.ok(Cl.uint(0)));
    
    // Verify game status
    const statusResult = simnet.callReadOnlyFn(
      'tic-tac-toe',
      'get-game-status',
      [Cl.uint(gameId)],
      player1
    );
    
    expect(statusResult.result).toBeOk(
      Cl.tuple({
        status: Cl.stringAscii("finished"),
        winner: Cl.some(Cl.standardPrincipal(player1)),
        "total-prize": Cl.uint(2000000),
        "is-draw": Cl.bool(false)
      })
    );
  });

});