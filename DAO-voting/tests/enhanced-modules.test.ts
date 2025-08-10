import { describe, it, expect, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const alice = accounts.get("wallet_1")!;
const bob = accounts.get("wallet_2")!;
const charlie = accounts.get("wallet_3")!;

describe("Enhanced DAO Modules Tests", () => {
  beforeEach(() => {
    // Reset simnet state for each test
  });

  describe("AccessControl Contract", () => {
    it("should initialize with default roles", () => {
      const initResponse = simnet.callPublicFn(
        "AccessControl",
        "initialize",
        [],
        deployer
      );
      expect(initResponse.result).toBeOk(Cl.bool(true));

      // Check if deployer has admin role
      const hasAdminRole = simnet.callReadOnlyFn(
        "AccessControl",
        "has-role",
        [Cl.principal(deployer), Cl.stringAscii("admin")],
        deployer
      );
      expect(hasAdminRole.result).toBeTrue();
    });

    it("should grant and revoke roles", () => {
      // Initialize
      simnet.callPublicFn("AccessControl", "initialize", [], deployer);

      // Grant proposer role to alice
      const grantResponse = simnet.callPublicFn(
        "AccessControl",
        "grant-role",
        [Cl.principal(alice), Cl.stringAscii("proposer")],
        deployer
      );
      expect(grantResponse.result).toBeOk(Cl.bool(true));

      // Check if alice has proposer role
      const hasRole = simnet.callReadOnlyFn(
        "AccessControl",
        "has-role",
        [Cl.principal(alice), Cl.stringAscii("proposer")],
        deployer
      );
      expect(hasRole.result).toBeTrue();
    });
  });

  describe("Events Contract", () => {
    it("should initialize and log events", () => {
      const initResponse = simnet.callPublicFn(
        "Events",
        "initialize",
        [Cl.principal(deployer)],
        deployer
      );
      expect(initResponse.result).toBeOk(Cl.bool(true));

      // Log an event
      const logResponse = simnet.callPublicFn(
        "Events",
        "log-event",
        [
          Cl.uint(1), // EVENT_PROPOSAL_CREATED
          Cl.principal(alice),
          Cl.some(Cl.principal(bob)),
          Cl.bufferFromUint8Array(new Uint8Array(32)),
          Cl.stringAscii("governance")
        ],
        deployer
      );
      expect(logResponse.result).toBeOk(Cl.uint(1));
    });
  });

  describe("Timelock Contract", () => {
    it("should initialize timelock", () => {
      const initResponse = simnet.callPublicFn(
        "Timelock",
        "initialize",
        [Cl.principal(deployer), Cl.uint(144)],
        deployer
      );
      expect(initResponse.result).toBeOk(Cl.bool(true));

      const admin = simnet.callReadOnlyFn(
        "Timelock",
        "get-admin",
        [],
        deployer
      );
      expect(admin.result).toBePrincipal(deployer);
    });
  });

  describe("Enhanced DAO Integration", () => {
    beforeEach(() => {
      // Setup basic tokens
      simnet.callPublicFn("DaoToken", "mint", [Cl.uint(10000000), Cl.principal(alice)], deployer);
      simnet.callPublicFn("DaoToken", "mint", [Cl.uint(5000000), Cl.principal(bob)], deployer);
    });

    it("should handle proposal creation with enhanced features", () => {
      // Create proposal with enhanced parameters
      const proposalResponse = simnet.callPublicFn(
        "Governed",
        "create-proposal",
        [
          Cl.stringAscii("Enhanced Proposal"),
          Cl.stringAscii("A proposal with enhanced governance features"),
          Cl.uint(1), // PROPOSAL_TYPE_TRANSFER
          Cl.some(Cl.principal(bob)),
          Cl.some(Cl.stringAscii("transfer")),
          Cl.some(Cl.list([Cl.bufferFromUint8Array(new Uint8Array(32))]))
        ],
        alice
      );
      expect(proposalResponse.result).toBeOk(Cl.uint(1));

      // Check proposal details
      const proposal = simnet.callReadOnlyFn(
        "Governed",
        "get-proposal",
        [Cl.uint(1)],
        deployer
      );
      expect(proposal.result).toBeSome();
    });

    it("should handle voting with strategy", () => {
      // Create proposal
      simnet.callPublicFn("Governed", "create-proposal", [
        Cl.stringAscii("Strategy Test"),
        Cl.stringAscii("Testing voting strategy"),
        Cl.uint(1),
        Cl.none(),
        Cl.none(),
        Cl.none()
      ], alice);

      // Advance to voting period
      simnet.mineEmptyBlocks(2);

      // Vote on proposal
      const voteResponse = simnet.callPublicFn(
        "Governed",
        "vote",
        [Cl.uint(1), Cl.uint(1)], // For
        alice
      );
      expect(voteResponse.result).toBeOk(Cl.bool(true));

      // Check vote was recorded
      const vote = simnet.callReadOnlyFn(
        "Governed",
        "get-vote",
        [Cl.uint(1), Cl.principal(alice)],
        deployer
      );
      expect(vote.result).toBeSome();
    });

    it("should handle treasury operations", () => {
      // Deposit to treasury
      const depositResponse = simnet.callPublicFn(
        "Treasury",
        "deposit",
        [Cl.uint(1000000)],
        alice
      );
      expect(depositResponse.result).toBeOk(Cl.bool(true));

      // Check balance
      const balance = simnet.callReadOnlyFn(
        "Treasury",
        "get-balance",
        [],
        deployer
      );
      expect(balance.result).toBeUint(1000000);
    });
  });
});
