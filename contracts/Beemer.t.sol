// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { Beemer } from "./Beemer.sol";

contract BeemerTest is Test {
    Beemer token;
    address alice;

    uint256 constant UNIT = 1e18;
    bytes32 constant REASON = "VESTING";

    function setUp() public {
        token = new Beemer();
        alice = makeAddr("alice");
        vm.warp(1_000);
    }

    // ── ERC20 ─────────────────────────────────────────────────────────────────

    function test_NameAndSymbol() public view {
        assertEq(token.name(), "Beemer");
        assertEq(token.symbol(), "BMMR");
    }

    function test_InitialSupplyIsOneBillion() public view {
        assertEq(token.totalSupply(), 1_000_000_000 * UNIT);
    }

    function test_DeployerReceivesEntireSupply() public view {
        assertEq(token.balanceOf(address(this)), token.totalSupply());
    }

    // ── lock() token movement ─────────────────────────────────────────────────

    function test_Lock_MovesTokensToContract() public {
        uint256 before = token.balanceOf(address(this));
        token.lock(REASON, 1_000 * UNIT, 7 days);
        assertEq(token.balanceOf(address(this)), before - 1_000 * UNIT);
        assertEq(token.balanceOf(address(token)), 1_000 * UNIT);
    }

    // ── transferWithLock() token movement ─────────────────────────────────────

    function test_TransferWithLock_DeductsSenderBalance() public {
        uint256 before = token.balanceOf(address(this));
        token.transferWithLock(alice, REASON, 500 * UNIT, 30 days);
        assertEq(token.balanceOf(address(this)), before - 500 * UNIT);
    }

    // ── totalBalanceOf() ──────────────────────────────────────────────────────

    function test_TotalBalanceOf_IncludesLockedAndFree() public {
        uint256 total = token.totalSupply();
        token.lock(REASON, 1_000 * UNIT, 7 days);
        assertEq(token.totalBalanceOf(address(this)), total);
    }

    function test_TotalBalanceOf_SumsMultipleLocks() public {
        bytes32 reason2 = "STAKING";
        token.lock(REASON, 1_000 * UNIT, 7 days);
        token.lock(reason2, 2_000 * UNIT, 30 days);
        uint256 free = token.balanceOf(address(this));
        assertEq(token.totalBalanceOf(address(this)), free + 3_000 * UNIT);
    }

    // ── increaseLockAmount() token movement ───────────────────────────────────

    function test_IncreaseLockAmount_MovesTokensToContract() public {
        token.lock(REASON, 1_000 * UNIT, 7 days);
        token.increaseLockAmount(REASON, 500 * UNIT);
        assertEq(token.balanceOf(address(token)), 1_500 * UNIT);
    }

    // ── unlock() token movement ───────────────────────────────────────────────

    function test_Unlock_ReturnsTokensToHolder() public {
        uint256 before = token.balanceOf(address(this));
        token.lock(REASON, 1_000 * UNIT, 1 days);
        vm.warp(block.timestamp + 1 days);
        token.unlock(address(this));
        assertEq(token.balanceOf(address(this)), before);
    }

    function test_Unlock_ReleasesMultipleReasons() public {
        bytes32 reason2 = "STAKING";
        token.lock(REASON, 1_000 * UNIT, 1 days);
        token.lock(reason2, 2_000 * UNIT, 1 days);
        uint256 before = token.balanceOf(address(this));

        vm.warp(block.timestamp + 1 days);
        uint256 released = token.unlock(address(this));

        assertEq(released, 3_000 * UNIT);
        assertEq(token.balanceOf(address(this)), before + 3_000 * UNIT);
    }
}
