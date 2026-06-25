// SPDX-License-Identifier: MPL-2.0
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract OwnableOperators is Ownable {
    mapping(address => bool) private _isOperator;

    constructor(address _owner) Ownable(_owner) {}

    event OperatorAdded(address indexed operator);

    modifier onlyOperator() {
        require(msg.sender == owner() || _isOperator[msg.sender], "Not an operator");
        _;
    }

    function addOperator(address operator) external onlyOwner {
        require(!_isOperator[operator], "Already an operator");
        _isOperator[operator] = true;
        emit OperatorAdded(operator);
    }

    function isOperator(address account) external view returns (bool) {
        return account == owner() || _isOperator[account];
    }
}
