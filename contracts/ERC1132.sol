// SPDX-License-Identifier: MPL-2.0
pragma solidity ^0.8.28;

/// @title ERC1132 — Token Locking Standard
/// @dev https://eips.ethereum.org/EIPS/eip-1132
abstract contract ERC1132 {
    string internal constant ALREADY_LOCKED = "Tokens already locked";
    string internal constant NOT_LOCKED = "No tokens locked";
    string internal constant AMOUNT_ZERO = "Amount can not be 0";

    struct LockToken {
        uint256 amount;
        uint256 validity;
        bool claimed;
    }

    mapping(address => bytes32[]) public lockReason;
    mapping(address => mapping(bytes32 => LockToken)) public locked;

    event Locked(address indexed _of, bytes32 indexed _reason, uint256 _amount, uint256 _validity);
    event Unlocked(address indexed _of, bytes32 indexed _reason, uint256 _amount);

    /// @notice Locks `_amount` of caller's tokens for `_reason` for `_time` seconds.
    function lock(bytes32 _reason, uint256 _amount, uint256 _time) public virtual returns (bool) {
        uint256 validUntil = block.timestamp + _time;

        require(tokensLocked(msg.sender, _reason) == 0, ALREADY_LOCKED);
        require(_amount != 0, AMOUNT_ZERO);

        if (locked[msg.sender][_reason].amount == 0)
            lockReason[msg.sender].push(_reason);

        locked[msg.sender][_reason] = LockToken(_amount, validUntil, false);

        emit Locked(msg.sender, _reason, _amount, validUntil);
        return true;
    }

    /// @notice Transfers `_amount` tokens to `_to` and locks them for `_reason` for `_time` seconds.
    function transferWithLock(address _to, bytes32 _reason, uint256 _amount, uint256 _time) public virtual returns (bool) {
        uint256 validUntil = block.timestamp + _time;

        require(tokensLocked(_to, _reason) == 0, ALREADY_LOCKED);
        require(_amount != 0, AMOUNT_ZERO);

        if (locked[_to][_reason].amount == 0)
            lockReason[_to].push(_reason);

        locked[_to][_reason] = LockToken(_amount, validUntil, false);

        emit Locked(_to, _reason, _amount, validUntil);
        return true;
    }

    /// @notice Returns currently locked tokens for `_of` under `_reason` (0 if already claimed).
    function tokensLocked(address _of, bytes32 _reason) public view virtual returns (uint256 amount) {
        if (!locked[_of][_reason].claimed)
            amount = locked[_of][_reason].amount;
    }

    /// @notice Returns tokens locked for `_of` under `_reason` that were still locked at `_time`.
    function tokensLockedAtTime(address _of, bytes32 _reason, uint256 _time) public view virtual returns (uint256 amount) {
        if (locked[_of][_reason].validity > _time)
            amount = locked[_of][_reason].amount;
    }

    /// @notice Returns transferable balance + all locked balances for `_of`.
    function totalBalanceOf(address _of) public view virtual returns (uint256 amount);

    /// @notice Extends the lock period for `_reason` by `_time` seconds.
    function extendLock(bytes32 _reason, uint256 _time) public virtual returns (bool) {
        require(tokensLocked(msg.sender, _reason) > 0, NOT_LOCKED);
        locked[msg.sender][_reason].validity += _time;
        emit Locked(msg.sender, _reason, locked[msg.sender][_reason].amount, locked[msg.sender][_reason].validity);
        return true;
    }

    /// @notice Adds `_amount` tokens to an existing lock for `_reason`.
    function increaseLockAmount(bytes32 _reason, uint256 _amount) public virtual returns (bool) {
        require(tokensLocked(msg.sender, _reason) > 0, NOT_LOCKED);
        require(_amount != 0, AMOUNT_ZERO);
        locked[msg.sender][_reason].amount += _amount;
        emit Locked(msg.sender, _reason, locked[msg.sender][_reason].amount, locked[msg.sender][_reason].validity);
        return true;
    }

    /// @notice Returns how many tokens under `_reason` are past their validity and unclaimed.
    function tokensUnlockable(address _of, bytes32 _reason) public view virtual returns (uint256 amount) {
        LockToken storage lt = locked[_of][_reason];
        if (lt.validity <= block.timestamp && !lt.claimed)
            amount = lt.amount;
    }

    /// @notice Releases all unlockable tokens for `_of` and returns the total amount freed.
    function unlock(address _of) public virtual returns (uint256 unlockableTokens) {
        for (uint256 i = 0; i < lockReason[_of].length; i++) {
            uint256 lockedTokens = tokensUnlockable(_of, lockReason[_of][i]);
            if (lockedTokens > 0) {
                unlockableTokens += lockedTokens;
                locked[_of][lockReason[_of][i]].claimed = true;
                emit Unlocked(_of, lockReason[_of][i], lockedTokens);
            }
        }
    }

    /// @notice Returns the total unlockable (expired, unclaimed) tokens for `_of`.
    function getUnlockableTokens(address _of) public view virtual returns (uint256 unlockableTokens) {
        for (uint256 i = 0; i < lockReason[_of].length; i++) {
            unlockableTokens += tokensUnlockable(_of, lockReason[_of][i]);
        }
    }
}
