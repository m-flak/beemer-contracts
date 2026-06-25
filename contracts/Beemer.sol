// SPDX-License-Identifier: MPL-2.0
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC1132Extended } from "./ERC1132Extended.sol";

contract Beemer is ERC20, ERC1132Extended {
    constructor() ERC20("Beemer", "BMMR") {
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }

    function lock(bytes32 _reason, uint256 _amount, uint256 _time) public override returns (bool) {
        _transfer(msg.sender, address(this), _amount);
        return super.lock(_reason, _amount, _time);
    }

    function transferWithLock(address _to, bytes32 _reason, uint256 _amount, uint256 _time) public override returns (bool) {
        _transfer(msg.sender, address(this), _amount);
        return super.transferWithLock(_to, _reason, _amount, _time);
    }

    function totalBalanceOf(address _of) public view override returns (uint256 amount) {
        amount = balanceOf(_of);
        for (uint256 i = 0; i < lockReason[_of].length; i++) {
            amount += tokensLocked(_of, lockReason[_of][i]);
        }
    }

    function increaseLockAmount(bytes32 _reason, uint256 _amount) public override returns (bool) {
        _transfer(msg.sender, address(this), _amount);
        return super.increaseLockAmount(_reason, _amount);
    }

    function unlock(address _of) public override returns (uint256 unlockableTokens) {
        unlockableTokens = super.unlock(_of);
        if (unlockableTokens > 0)
            _transfer(address(this), _of, unlockableTokens);
    }
}
