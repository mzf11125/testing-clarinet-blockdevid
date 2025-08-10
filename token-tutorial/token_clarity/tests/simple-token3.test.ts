import { describe, it, expect, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

describe("Simple Token Tests", () => {
  beforeEach(() => {
    // Reset simnet state before each test
    simnet.setEpoch("2.4");
  });

  describe("Token Metadata", () => {
    it("should return correct token name", () => {
      const { result } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-name",
        [],
        deployer
      );
      expect(result).toBeOk(Cl.stringAscii("Token DeDanzi"));
    });

    it("should return correct token symbol", () => {
      const { result } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-symbol",
        [],
        deployer
      );
      expect(result).toBeOk(Cl.stringAscii("DDZ"));
    });

    it("should return correct decimals", () => {
      const { result } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-decimals",
        [],
        deployer
      );
      expect(result).toBeOk(Cl.uint(6));
    });

    it("should return correct token URI", () => {
      const { result } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-token-uri",
        [],
        deployer
      );
      expect(result).toBeOk(
        Cl.some(Cl.stringUtf8("https://workshop.blockdev.id/token.json"))
      );
    });
  });

  describe("Token Supply and Balance", () => {
    it("should return zero total supply initially", () => {
      const { result } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-total-supply",
        [],
        deployer
      );
      expect(result).toBeOk(Cl.uint(0));
    });

    it("should return zero balance for any address initially", () => {
      const { result } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-balance",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(result).toBeOk(Cl.uint(0));
    });
  });

  describe("Minting", () => {
    it("should allow contract owner to mint tokens", () => {
      const mintAmount = 1000000; // 1 token with 6 decimals

      const { result } = simnet.callPublicFn(
        "simple-token3",
        "mint",
        [Cl.uint(mintAmount), Cl.principal(wallet1)],
        deployer
      );

      expect(result).toBeOk(Cl.bool(true));

      // Check balance was updated
      const { result: balance } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-balance",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(balance).toBeOk(Cl.uint(mintAmount));

      // Check total supply was updated
      const { result: totalSupply } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-total-supply",
        [],
        deployer
      );
      expect(totalSupply).toBeOk(Cl.uint(mintAmount));
    });

    it("should not allow non-owner to mint tokens", () => {
      const mintAmount = 1000000;

      const { result } = simnet.callPublicFn(
        "simple-token3",
        "mint",
        [Cl.uint(mintAmount), Cl.principal(wallet1)],
        wallet1 // wallet1 is not the owner
      );

      expect(result).toBeErr(Cl.uint(100)); // err-owner-only
    });

    it("should allow minting to multiple addresses", () => {
      const mintAmount = 500000;

      // Mint to wallet1
      simnet.callPublicFn(
        "simple-token3",
        "mint",
        [Cl.uint(mintAmount), Cl.principal(wallet1)],
        deployer
      );

      // Mint to wallet2
      simnet.callPublicFn(
        "simple-token3",
        "mint",
        [Cl.uint(mintAmount), Cl.principal(wallet2)],
        deployer
      );

      // Check individual balances
      const { result: balance1 } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-balance",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(balance1).toBeOk(Cl.uint(mintAmount));

      const { result: balance2 } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-balance",
        [Cl.principal(wallet2)],
        deployer
      );
      expect(balance2).toBeOk(Cl.uint(mintAmount));

      // Check total supply
      const { result: totalSupply } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-total-supply",
        [],
        deployer
      );
      expect(totalSupply).toBeOk(Cl.uint(mintAmount * 2));
    });
  });

  describe("Transfer", () => {
    beforeEach(() => {
      // Mint some tokens to wallet1 for transfer tests
      simnet.callPublicFn(
        "simple-token3",
        "mint",
        [Cl.uint(1000000), Cl.principal(wallet1)],
        deployer
      );
    });

    it("should allow token owner to transfer tokens", () => {
      const transferAmount = 500000;

      const { result } = simnet.callPublicFn(
        "simple-token3",
        "transfer",
        [
          Cl.uint(transferAmount),
          Cl.principal(wallet1),
          Cl.principal(wallet2),
          Cl.none(),
        ],
        wallet1 // wallet1 is the sender
      );

      expect(result).toBeOk(Cl.bool(true));

      // Check sender balance decreased
      const { result: senderBalance } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-balance",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(senderBalance).toBeOk(Cl.uint(500000));

      // Check recipient balance increased
      const { result: recipientBalance } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-balance",
        [Cl.principal(wallet2)],
        deployer
      );
      expect(recipientBalance).toBeOk(Cl.uint(transferAmount));
    });

    it("should not allow non-token-owner to transfer tokens", () => {
      const transferAmount = 500000;

      const { result } = simnet.callPublicFn(
        "simple-token3",
        "transfer",
        [
          Cl.uint(transferAmount),
          Cl.principal(wallet1),
          Cl.principal(wallet2),
          Cl.none(),
        ],
        wallet2 // wallet2 is not the owner of the tokens
      );

      expect(result).toBeErr(Cl.uint(101)); // err-not-token-owner
    });

    it("should fail when trying to transfer more tokens than available", () => {
      const transferAmount = 2000000; // More than the 1000000 minted

      const { result } = simnet.callPublicFn(
        "simple-token3",
        "transfer",
        [
          Cl.uint(transferAmount),
          Cl.principal(wallet1),
          Cl.principal(wallet2),
          Cl.none(),
        ],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(1)); // Standard insufficient balance error
    });

    it("should allow transfer with memo", () => {
      const transferAmount = 100000;
      const memo = new TextEncoder().encode("Payment for services");

      const { result } = simnet.callPublicFn(
        "simple-token3",
        "transfer",
        [
          Cl.uint(transferAmount),
          Cl.principal(wallet1),
          Cl.principal(wallet2),
          Cl.some(Cl.bufferFromUtf8("Payment for services")),
        ],
        wallet1
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should maintain total supply after transfers", () => {
      const transferAmount = 300000;

      // Transfer tokens
      simnet.callPublicFn(
        "simple-token3",
        "transfer",
        [
          Cl.uint(transferAmount),
          Cl.principal(wallet1),
          Cl.principal(wallet2),
          Cl.none(),
        ],
        wallet1
      );

      // Total supply should remain the same
      const { result: totalSupply } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-total-supply",
        [],
        deployer
      );
      expect(totalSupply).toBeOk(Cl.uint(1000000));
    });

    it("should allow transferring zero amount", () => {
      const { result } = simnet.callPublicFn(
        "simple-token3",
        "transfer",
        [
          Cl.uint(0),
          Cl.principal(wallet1),
          Cl.principal(wallet2),
          Cl.none(),
        ],
        wallet1
      );

      expect(result).toBeOk(Cl.bool(true));
    });
  });

  describe("Edge Cases", () => {
    it("should handle multiple mint operations correctly", () => {
      const mintAmount1 = 100000;
      const mintAmount2 = 200000;
      const mintAmount3 = 300000;

      // Multiple mints to same address
      simnet.callPublicFn(
        "simple-token3",
        "mint",
        [Cl.uint(mintAmount1), Cl.principal(wallet1)],
        deployer
      );

      simnet.callPublicFn(
        "simple-token3",
        "mint",
        [Cl.uint(mintAmount2), Cl.principal(wallet1)],
        deployer
      );

      simnet.callPublicFn(
        "simple-token3",
        "mint",
        [Cl.uint(mintAmount3), Cl.principal(wallet1)],
        deployer
      );

      // Check final balance
      const { result: balance } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-balance",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(balance).toBeOk(Cl.uint(mintAmount1 + mintAmount2 + mintAmount3));

      // Check total supply
      const { result: totalSupply } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-total-supply",
        [],
        deployer
      );
      expect(totalSupply).toBeOk(Cl.uint(mintAmount1 + mintAmount2 + mintAmount3));
    });

    it("should handle transfer to self", () => {
      // Mint tokens first
      simnet.callPublicFn(
        "simple-token3",
        "mint",
        [Cl.uint(1000000), Cl.principal(wallet1)],
        deployer
      );

      const transferAmount = 500000;

      const { result } = simnet.callPublicFn(
        "simple-token3",
        "transfer",
        [
          Cl.uint(transferAmount),
          Cl.principal(wallet1),
          Cl.principal(wallet1), // Transfer to self
          Cl.none(),
        ],
        wallet1
      );

      expect(result).toBeOk(Cl.bool(true));

      // Balance should remain the same
      const { result: balance } = simnet.callReadOnlyFn(
        "simple-token3",
        "get-balance",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(balance).toBeOk(Cl.uint(1000000));
    });
  });
});