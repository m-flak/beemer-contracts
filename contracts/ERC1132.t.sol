// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { Beemer } from "./Beemer.sol";
import { ERC1132 } from "./ERC1132.sol";

contract ERC1132Test is Test {
    Beemer token;
    address alice;

    uint256 constant UNIT = 1e18;
    bytes32 constant REASON = "VESTING";

    function setUp() public {
        token = new Beemer();
        alice = makeAddr("alice");
        vm.warp(1_000);
    }

    // ── lock() ────────────────────────────────────────────────────────────────

    function test_Lock_TracksLockedAmount() public {
        token.lock(REASON, 1_000 * UNIT, 7 days);
        assertEq(token.tokensLocked(address(this), REASON), 1_000 * UNIT);
    }

    function test_Lock_EmitsLockedEvent() public {
        uint256 expiry = block.timestamp + 7 days;
        vm.expectEmit(true, true, false, true);
        emit ERC1132.Locked(address(this), REASON, 1_000 * UNIT, expiry);
        token.lock(REASON, 1_000 * UNIT, 7 days);
    }

    function test_Lock_RevertsIfAlreadyLocked() public {
        token.lock(REASON, 500 * UNIT, 7 days);
        vm.expectRevert("Tokens already locked");
        token.lock(REASON, 500 * UNIT, 7 days);
    }

    function test_Lock_RevertsIfAmountZero() public {
        vm.expectRevert("Amount can not be 0");
        token.lock(REASON, 0, 7 days);
    }

    // ── transferWithLock() ────────────────────────────────────────────────────

    function test_TransferWithLock_LocksForRecipient() public {
        token.transferWithLock(alice, REASON, 500 * UNIT, 30 days);
        assertEq(token.tokensLocked(alice, REASON), 500 * UNIT);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_TransferWithLock_RevertsIfAlreadyLocked() public {
        token.transferWithLock(alice, REASON, 500 * UNIT, 30 days);
        vm.expectRevert("Tokens already locked");
        token.transferWithLock(alice, REASON, 100 * UNIT, 30 days);
    }

    function test_TransferWithLock_RevertsIfAmountZero() public {
        vm.expectRevert("Amount can not be 0");
        token.transferWithLock(alice, REASON, 0, 30 days);
    }

    // ── tokensLocked() ────────────────────────────────────────────────────────

    function test_TokensLocked_ReturnsZeroAfterClaimed() public {
        token.lock(REASON, 1_000 * UNIT, 1 days);
        vm.warp(block.timestamp + 1 days + 1);
        token.unlock(address(this));
        assertEq(token.tokensLocked(address(this), REASON), 0);
    }

    // ── tokensLockedAtTime() ──────────────────────────────────────────────────

    function test_TokensLockedAtTime() public {
        token.lock(REASON, 1_000 * UNIT, 7 days);
        uint256 expiry = block.timestamp + 7 days;

        assertEq(token.tokensLockedAtTime(address(this), REASON, block.timestamp), 1_000 * UNIT);
        assertEq(token.tokensLockedAtTime(address(this), REASON, expiry - 1), 1_000 * UNIT);
        assertEq(token.tokensLockedAtTime(address(this), REASON, expiry), 0);
        assertEq(token.tokensLockedAtTime(address(this), REASON, expiry + 1 days), 0);
    }

    // ── extendLock() ──────────────────────────────────────────────────────────

    function test_ExtendLock_PostponesExpiry() public {
        token.lock(REASON, 1_000 * UNIT, 7 days);
        uint256 originalExpiry = block.timestamp + 7 days;

        token.extendLock(REASON, 3 days);

        vm.warp(originalExpiry);
        assertEq(token.tokensUnlockable(address(this), REASON), 0);

        vm.warp(originalExpiry + 3 days);
        assertEq(token.tokensUnlockable(address(this), REASON), 1_000 * UNIT);
    }

    function test_ExtendLock_RevertsIfNotLocked() public {
        vm.expectRevert("No tokens locked");
        token.extendLock(REASON, 1 days);
    }

    // ── increaseLockAmount() ──────────────────────────────────────────────────

    function test_IncreaseLockAmount_AddsToLocked() public {
        token.lock(REASON, 1_000 * UNIT, 7 days);
        token.increaseLockAmount(REASON, 500 * UNIT);
        assertEq(token.tokensLocked(address(this), REASON), 1_500 * UNIT);
    }

    function test_IncreaseLockAmount_RevertsIfNotLocked() public {
        vm.expectRevert("No tokens locked");
        token.increaseLockAmount(REASON, 500 * UNIT);
    }

    function test_IncreaseLockAmount_RevertsIfAmountZero() public {
        token.lock(REASON, 1_000 * UNIT, 7 days);
        vm.expectRevert("Amount can not be 0");
        token.increaseLockAmount(REASON, 0);
    }

    // ── tokensUnlockable() ────────────────────────────────────────────────────

    function test_TokensUnlockable_ZeroBeforeExpiry() public {
        token.lock(REASON, 1_000 * UNIT, 7 days);
        vm.warp(block.timestamp + 7 days - 1);
        assertEq(token.tokensUnlockable(address(this), REASON), 0);
    }

    function test_TokensUnlockable_ReturnsAmountAtExpiry() public {
        token.lock(REASON, 1_000 * UNIT, 7 days);
        vm.warp(block.timestamp + 7 days);
        assertEq(token.tokensUnlockable(address(this), REASON), 1_000 * UNIT);
    }

    function test_TokensUnlockable_ZeroAfterClaimed() public {
        token.lock(REASON, 1_000 * UNIT, 1 days);
        vm.warp(block.timestamp + 1 days);
        token.unlock(address(this));
        assertEq(token.tokensUnlockable(address(this), REASON), 0);
    }

    // ── unlock() ──────────────────────────────────────────────────────────────

    function test_Unlock_EmitsUnlockedEvent() public {
        token.lock(REASON, 1_000 * UNIT, 1 days);
        vm.warp(block.timestamp + 1 days);
        vm.expectEmit(true, true, false, true);
        emit ERC1132.Unlocked(address(this), REASON, 1_000 * UNIT);
        token.unlock(address(this));
    }

    function test_Unlock_SkipsStillLockedReasons() public {
        bytes32 reason2 = "STAKING";
        token.lock(REASON, 1_000 * UNIT, 1 days);
        token.lock(reason2, 2_000 * UNIT, 30 days);

        vm.warp(block.timestamp + 1 days);
        uint256 released = token.unlock(address(this));

        assertEq(released, 1_000 * UNIT);
        assertEq(token.tokensLocked(address(this), reason2), 2_000 * UNIT);
    }

    // ── getUnlockableTokens() ─────────────────────────────────────────────────

    function test_GetUnlockableTokens_SumsAllExpiredReasons() public {
        bytes32 reason2 = "STAKING";
        token.lock(REASON, 1_000 * UNIT, 1 days);
        token.lock(reason2, 2_000 * UNIT, 1 days);

        vm.warp(block.timestamp + 1 days);
        assertEq(token.getUnlockableTokens(address(this)), 3_000 * UNIT);
    }

    function test_GetUnlockableTokens_ZeroBeforeExpiry() public {
        token.lock(REASON, 1_000 * UNIT, 7 days);
        assertEq(token.getUnlockableTokens(address(this)), 0);
    }

    // ── totalLocked() (ERC1132Extended) ──────────────────────────────────────

    function test_TotalLocked_IncreasesOnLock() public {
        token.lock(REASON, 1_000 * UNIT, 7 days);
        assertEq(token.totalLocked(), 1_000 * UNIT);
    }

    function test_TotalLocked_IncreasesOnTransferWithLock() public {
        token.transferWithLock(alice, REASON, 500 * UNIT, 7 days);
        assertEq(token.totalLocked(), 500 * UNIT);
    }

    function test_TotalLocked_IncreasesOnIncreaseLockAmount() public {
        token.lock(REASON, 1_000 * UNIT, 7 days);
        token.increaseLockAmount(REASON, 500 * UNIT);
        assertEq(token.totalLocked(), 1_500 * UNIT);
    }

    function test_TotalLocked_DecreasesOnUnlock() public {
        token.lock(REASON, 1_000 * UNIT, 1 days);
        vm.warp(block.timestamp + 1 days);
        token.unlock(address(this));
        assertEq(token.totalLocked(), 0);
    }
}
