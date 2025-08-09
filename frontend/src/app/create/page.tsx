"use client";

import { GameBoard } from "@/components/game-board";
import { useStacks } from "@/hooks/use-stacks";
import { EMPTY_BOARD, Move } from "@/lib/contract";
import { formatStx, parseStx } from "@/lib/stx-utils";
import { useState } from "react";

export default function CreateGame() {
  const { stxBalance, userData, connectWallet, handleCreateGame } = useStacks();

  const [betAmount, setBetAmount] = useState<number | "">(0);
  // When creating a new game, the initial board is entirely empty
  const [board, setBoard] = useState(EMPTY_BOARD);

  function onCellClick(index: number) {
    // Update the board to be the empty board + the move played by the user
    // Since this is inside 'Create Game', the user's move is the very first move and therefore always an X
    const tempBoard = [...EMPTY_BOARD];
    tempBoard[index] = Move.X;
    setBoard(tempBoard);
  }

  async function onCreateGame() {
    console.log("onCreateGame called"); // Debug log
    
    // Validate bet amount
    const numericBetAmount = typeof betAmount === "string" ? parseFloat(betAmount) : betAmount;
    console.log("Bet amount validation:", { betAmount, numericBetAmount }); // Debug log
    
    if (!numericBetAmount || numericBetAmount <= 0) {
      window.alert("Please enter a valid bet amount greater than 0");
      return;
    }

    // Find the moveIndex (i.e. the cell) where the user played their move
    const moveIndex = board.findIndex((cell) => cell !== Move.EMPTY);
    console.log("Move validation:", { board, moveIndex }); // Debug log
    
    if (moveIndex === -1) {
      window.alert("Please make a move on the board first by clicking on any cell");
      return;
    }

    const move = Move.X;
    const parsedBetAmount = parseStx(numericBetAmount);
    console.log("Creating game with:", { 
      betAmount: numericBetAmount, 
      parsedBetAmount, 
      moveIndex, 
      move, 
      userData: !!userData 
    }); // Enhanced debug log
    
    try {
      // Trigger the onchain transaction popup
      await handleCreateGame(parsedBetAmount, moveIndex, move);
      console.log("handleCreateGame completed successfully");
    } catch (error) {
      console.error("Error in handleCreateGame:", error);
      window.alert("Failed to create game: " + (error as Error).message);
    }
  }

  return (
    <section className="flex flex-col items-center py-20">
      <div className="text-center mb-20">
        <h1 className="text-4xl font-bold">Create Game</h1>
        <span className="text-sm text-gray-500">
          Make a bet and play your first move
        </span>
      </div>

      <div className="flex flex-col gap-4 w-[400px]">
        <GameBoard
          board={board}
          onCellClick={onCellClick}
          nextMove={Move.X}
          cellClassName="size-32 text-6xl"
        />

        <div className="flex items-center gap-2 w-full">
          <span className="">Bet: </span>
          <input
            type="number"
            step="0.1"
            min="0"
            className="w-full rounded bg-gray-800 px-1"
            placeholder="0"
            value={betAmount === 0 ? "" : betAmount}
            onChange={(e) => {
              const value = e.target.value;
              if (value === "") {
                setBetAmount("");
              } else {
                const numValue = parseFloat(value);
                setBetAmount(isNaN(numValue) ? "" : numValue);
              }
            }}
          />
          <div
            className="text-xs px-1 py-0.5 cursor-pointer hover:bg-gray-700 bg-gray-600 border border-gray-600 rounded"
            onClick={() => {
              const maxAmount = formatStx(stxBalance);
              setBetAmount(maxAmount);
            }}
          >
            Max
          </div>
        </div>

        {userData ? (
          <button
            type="button"
            className="bg-blue-500 text-white px-4 py-2 rounded"
            onClick={onCreateGame}
          >
            Create Game
          </button>
        ) : (
          <button
            type="button"
            onClick={connectWallet}
            className="bg-blue-500 text-white px-4 py-2 rounded"
          >
            Connect Wallet
          </button>
        )}
      </div>
    </section>
  );
}