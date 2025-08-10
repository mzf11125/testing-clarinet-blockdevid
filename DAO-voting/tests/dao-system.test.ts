import { describe, it, expect, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const alice = accounts.get("wallet_1")!;
const bob = accounts.get("wallet_2")!;
const charlie = accounts.get("wallet_3")!;

describe("DAO System Integration Tests", () => {
  beforeEach(() => {
    // Reset simnet state for each test
  });

  describe("DaoToken Contract", () => {
    it("should deploy and initialize token contract", () => {
      const response = simnet.callReadOnlyFn(
        "DaoToken",
        "get-name",
        [],
        deployer
      );
      expect(response.result).toBeOk(Cl.stringAscii("DAO Governance Token"));
    });

    it("should mint tokens to deployer", () => {
      const mintResponse = simnet.callPublicFn(
        "DaoToken",
        "mint",
        [Cl.uint(1000000), Cl.principal(alice)],
        deployer
      );
      expect(mintResponse.result).toBeOk(Cl.bool(true));

      const balanceResponse = simnet.callReadOnlyFn(
        "DaoToken",
        "get-balance",
        [Cl.principal(alice)],
        deployer
      );
      expect(balanceResponse.result).toBeOk(Cl.uint(1000000));
    });

    it("should allow token transfers", () => {
      // First mint tokens to alice
      simnet.callPublicFn(
        "DaoToken",
        "mint",
        [Cl.uint(1000000), Cl.principal(alice)],
        deployer
      );

      // Transfer tokens from alice to bob
      const transferResponse = simnet.callPublicFn(
        "DaoToken",
        "transfer",
        [Cl.uint(500000), Cl.principal(alice), Cl.principal(bob), Cl.none()],
        alice
      );
      expect(transferResponse.result).toBeOk(Cl.bool(true));

      // Check balances
      const aliceBalance = simnet.callReadOnlyFn(
        "DaoToken",
        "get-balance",
        [Cl.principal(alice)],
        deployer
      );
      expect(aliceBalance.result).toBeOk(Cl.uint(500000));

      const bobBalance = simnet.callReadOnlyFn(
        "DaoToken",
        "get-balance",
        [Cl.principal(bob)],
        deployer
      );
      expect(bobBalance.result).toBeOk(Cl.uint(500000));
    });

    it("should handle delegation", () => {
      // Mint tokens to alice
      simnet.callPublicFn(
        "DaoToken",
        "mint",
        [Cl.uint(1000000), Cl.principal(alice)],
        deployer
      );

      // Alice delegates to bob
      const delegateResponse = simnet.callPublicFn(
        "DaoToken",
        "delegate",
        [Cl.principal(bob)],
        alice
      );
      expect(delegateResponse.result).toBeOk(Cl.bool(true));

      // Check delegation
      const delegateResult = simnet.callReadOnlyFn(
        "DaoToken",
        "get-delegate",
        [Cl.principal(alice)],
        deployer
      );
      expect(delegateResult.result).toBeSome(Cl.principal(bob));

      // Check voting power
      const votingPower = simnet.callReadOnlyFn(
        "DaoToken",
        "get-voting-power",
        [Cl.principal(alice)],
        deployer
      );
      expect(votingPower.result).toBeUint(1000000);
    });
  });

  describe("Governed Contract", () => {
    beforeEach(() => {
      // Setup: mint tokens to alice for proposal creation
      simnet.callPublicFn(
        "DaoToken",
        "mint",
        [Cl.uint(2000000), Cl.principal(alice)],
        deployer
      );
      simnet.callPublicFn(
        "DaoToken",
        "mint",
        [Cl.uint(1000000), Cl.principal(bob)],
        deployer
      );
      simnet.callPublicFn(
        "DaoToken",
        "mint",
        [Cl.uint(1000000), Cl.principal(charlie)],
        deployer
      );
    });

    it("should create a proposal", () => {
      const proposalResponse = simnet.callPublicFn(
        "Governed",
        "create-proposal",
        [
          Cl.stringAscii("Test Proposal"),
          Cl.stringAscii("This is a test proposal for the DAO"),
          Cl.uint(1), // PROPOSAL_TYPE_TRANSFER
          Cl.some(Cl.principal(bob)),
          Cl.some(Cl.stringAscii("transfer")),
          Cl.some(Cl.list([Cl.bufferFromUint8Array(new Uint8Array(32))]))
        ],
        alice
      );
      expect(proposalResponse.result).toBeOk(Cl.uint(1));
    });

    it("should allow voting on proposals", () => {
      // Create proposal
      simnet.callPublicFn(
        "Governed",
        "create-proposal",
        [
          Cl.stringAscii("Test Proposal"),
          Cl.stringAscii("This is a test proposal for the DAO"),
          Cl.uint(1),
          Cl.some(Cl.principal(bob)),
          Cl.some(Cl.stringAscii("transfer")),
          Cl.some(Cl.list([Cl.bufferFromUint8Array(new Uint8Array(32))]))
        ],
        alice
      );

      // Advance to voting period
      simnet.mineEmptyBlocks(2);

      // Vote on proposal
      const voteResponse = simnet.callPublicFn(
        "Governed",
        "vote",
        [Cl.uint(1), Cl.uint(1)], // proposal-id: 1, vote-type: 1 (for)
        alice
      );
      expect(voteResponse.result).toBeOk(Cl.bool(true));

      // Bob votes against
      const bobVoteResponse = simnet.callPublicFn(
        "Governed",
        "vote",
        [Cl.uint(1), Cl.uint(2)], // vote-type: 2 (against)
        bob
      );
      expect(bobVoteResponse.result).toBeOk(Cl.bool(true));
    });

    it("should get proposal status", () => {
      // Create proposal
      simnet.callPublicFn(
        "Governed",
        "create-proposal",
        [
          Cl.stringAscii("Test Proposal"),
          Cl.stringAscii("This is a test proposal for the DAO"),
          Cl.uint(1),
          Cl.some(Cl.principal(bob)),
          Cl.some(Cl.stringAscii("transfer")),
          Cl.some(Cl.list([Cl.bufferFromUint8Array(new Uint8Array(32))]))
        ],
        alice
      );

      const statusResponse = simnet.callReadOnlyFn(
        "Governed",
        "get-proposal-status",
        [Cl.uint(1)],
        deployer
      );
      expect(statusResponse.result).toBeSome();
    });
  });

  describe("Treasury Contract", () => {
    it("should accept STX deposits", () => {
      const depositResponse = simnet.callPublicFn(
        "Treasury",
        "deposit",
        [Cl.uint(1000000)],
        alice
      );
      expect(depositResponse.result).toBeOk(Cl.bool(true));

      const balanceResponse = simnet.callReadOnlyFn(
        "Treasury",
        "get-balance",
        [],
        deployer
      );
      expect(balanceResponse.result).toBeUint(1000000);
    });
  });

  describe("VotingStrategy Contract", () => {
    it("should calculate voting power correctly", () => {
      // Mint tokens to alice
      simnet.callPublicFn(
        "DaoToken",
        "mint",
        [Cl.uint(1000000), Cl.principal(alice)],
        deployer
      );

      const votingPowerResponse = simnet.callPublicFn(
        "VotingStrategy",
        "calculate-voting-power",
        [Cl.principal(alice), Cl.uint(1), Cl.uint(1000000)],
        deployer
      );
      expect(votingPowerResponse.result).toBeOk(Cl.uint(1000000));
    });
  });

  describe("DaoFactory Contract", () => {
    it("should create DAO templates", () => {
      const templateResponse = simnet.callPublicFn(
        "DaoFactory",
        "create-dao-template",
        [
          Cl.stringAscii("Standard DAO"),
          Cl.stringAscii("A standard DAO template"),
          Cl.uint(1008), // voting-period
          Cl.uint(144),  // execution-delay
          Cl.uint(2000), // quorum-threshold
          Cl.uint(5100), // approval-threshold
          Cl.uint(1000000) // min-voting-power
        ],
        deployer
      );
      expect(templateResponse.result).toBeOk(Cl.uint(1));
    });

    it("should deploy new DAOs", () => {
      const daoResponse = simnet.callPublicFn(
        "DaoFactory",
        "deploy-dao",
        [
          Cl.stringAscii("Test DAO"),
          Cl.stringAscii("A test DAO instance"),
          Cl.stringAscii("TEST"),
          Cl.stringAscii("TST"),
          Cl.uint(1000000000),
          Cl.none()
        ],
        alice
      );
      expect(daoResponse.result).toBeOk(Cl.uint(1));
    });
  });

  describe("End-to-End DAO Workflow", () => {
    it("should complete full proposal lifecycle", () => {
      // 1. Setup: Mint tokens to participants
      simnet.callPublicFn("DaoToken", "mint", [Cl.uint(5000000), Cl.principal(alice)], deployer);
      simnet.callPublicFn("DaoToken", "mint", [Cl.uint(3000000), Cl.principal(bob)], deployer);
      simnet.callPublicFn("DaoToken", "mint", [Cl.uint(2000000), Cl.principal(charlie)], deployer);

      // 2. Alice creates a proposal
      const proposalResponse = simnet.callPublicFn(
        "Governed",
        "create-proposal",
        [
          Cl.stringAscii("Fund Project X"),
          Cl.stringAscii("Proposal to fund project X with 1000 STX"),
          Cl.uint(1), // PROPOSAL_TYPE_TRANSFER
          Cl.some(Cl.principal(bob)), // recipient
          Cl.some(Cl.stringAscii("transfer")),
          Cl.some(Cl.list([Cl.bufferFromUint8Array(new Uint8Array(32))]))
        ],
        alice
      );
      expect(proposalResponse.result).toBeOk(Cl.uint(1));

      // 3. Advance to voting period
      simnet.mineEmptyBlocks(2);

      // 4. Participants vote
      simnet.callPublicFn("Governed", "vote", [Cl.uint(1), Cl.uint(1)], alice); // For
      simnet.callPublicFn("Governed", "vote", [Cl.uint(1), Cl.uint(1)], bob);   // For
      simnet.callPublicFn("Governed", "vote", [Cl.uint(1), Cl.uint(2)], charlie); // Against

      // 5. Check proposal status after voting
      const statusAfterVoting = simnet.callReadOnlyFn(
        "Governed",
        "get-proposal-status",
        [Cl.uint(1)],
        deployer
      );
      expect(statusAfterVoting.result).toBeSome();

      // 6. Advance past voting period
      simnet.mineEmptyBlocks(1010);

      // 7. Check if proposal passed
      const finalStatus = simnet.callReadOnlyFn(
        "Governed",
        "get-proposal-status",
        [Cl.uint(1)],
        deployer
      );
      expect(finalStatus.result).toBeSome();

      // 8. Advance past execution delay
      simnet.mineEmptyBlocks(150);

      // 9. Execute proposal
      const executeResponse = simnet.callPublicFn(
        "Governed",
        "execute-proposal",
        [Cl.uint(1)],
        alice
      );
      expect(executeResponse.result).toBeOk(Cl.bool(true));
    });
  });
});
