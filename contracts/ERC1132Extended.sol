// SPDX-License-Identifier: MPL-2.0
pragma solidity ^0.8.28;

import { ERC1132 } from "./ERC1132.sol";

abstract contract ERC1132Extended is ERC1132 {
    uint256 internal _totalLocked;

    function totalLocked() public view returns (uint256) { return _totalLocked; }

    function lock(bytes32 _reason, uint256 _amount, uint256 _time) public virtual override returns (bool) {
        bool result = super.lock(_reason, _amount, _time);
        _totalLocked += _amount;
        return result;
    }

    function transferWithLock(address _to, bytes32 _reason, uint256 _amount, uint256 _time) public virtual override returns (bool) {
        bool result = super.transferWithLock(_to, _reason, _amount, _time);
        _totalLocked += _amount;
        return result;
    }

    function increaseLockAmount(bytes32 _reason, uint256 _amount) public virtual override returns (bool) {
        bool result = super.increaseLockAmount(_reason, _amount);
        _totalLocked += _amount;
        return result;
    }

    function unlock(address _of) public virtual override returns (uint256 unlockableTokens) {
        unlockableTokens = super.unlock(_of);
        _totalLocked -= unlockableTokens;
    }
}
