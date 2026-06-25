// SPDX-License-Identifier: MPL-2.0
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OwnableOperators } from "./OwnableOperators.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { ERC1132Extended } from "./ERC1132Extended.sol";
import { IWETH } from "./interfaces/IWETH.sol";

/// @notice Holds fee tokens collected by FeeFarm and distributes them to BMMR lockables
///         via Merkle-verified epochs.
///
/// Flow:
///   1. FeeFarm.collect() transfers fee tokens directly to this contract.
///   2. The cron job snapshots all locked BMMR balances at a chosen block, computes each
///      user's pro-rata reward, and builds a Merkle tree with leaves:
///        keccak256(keccak256(abi.encode(user, amount)))
///   3. Owner calls createEpoch() with the token, total amount, and Merkle root.
///   4. Users call claim() with their amount and a Merkle proof.
contract FeeVault is OwnableOperators, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Epoch {
        bytes32 merkleRoot;
        address token;
        uint256 totalAmount;
        string treeUri;
    }

    uint256 public epochCount;
    mapping(uint256 => Epoch) public epochs;
    mapping(address => mapping(uint256 => bool)) public claimed;

    ERC1132Extended public immutable lockable;
    IWETH public immutable wrappedNative;
    uint256 public targetRatePerLockable;

    event EpochCreated(uint256 indexed epochId, address indexed token, uint256 totalAmount, bytes32 merkleRoot, string treeUri);
    event Claimed(address indexed user, uint256 indexed epochId, address indexed token, uint256 amount);
    event TargetRateSet(uint256 rate);

    constructor(address _owner, address _lockable, address _wrappedNative) OwnableOperators(_owner) {
        lockable = ERC1132Extended(_lockable);
        wrappedNative = IWETH(_wrappedNative);
    }

    function setTargetRate(uint256 _rate) external onlyOperator {
        targetRatePerLockable = _rate;
        emit TargetRateSet(_rate);
    }

    /// @notice Returns the shortfall of `token` needed to satisfy all current lockables
    ///         at the configured rate, accounting for the vault's existing balance.
    function recommendedSeed(address token) external view returns (uint256) {
        uint256 needed = (lockable.totalLocked() * targetRatePerLockable) / 1e18;
        uint256 have   = IERC20(token).balanceOf(address(this));
        return needed > have ? needed - have : 0;
    }

    receive() external payable {
        wrappedNative.deposit{value: msg.value}();
    }

    function withdraw(address recipient, uint256 amount) external onlyOwner {
        IERC20(address(wrappedNative)).safeTransfer(recipient, amount);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    /// @notice Registers a new reward epoch. Tokens must already be in this contract
    ///         (sent by FeeFarm.collect()). The Merkle root encodes each eligible
    ///         lockable's reward amount as computed off-chain at the snapshot block.
    function createEpoch(address token, uint256 totalAmount, bytes32 merkleRoot, string calldata treeUri)
        external onlyOperator
    {
        require(IERC20(token).balanceOf(address(this)) >= totalAmount, "Insufficient balance");
        uint256 epochId = epochCount++;
        epochs[epochId] = Epoch({ merkleRoot: merkleRoot, token: token, totalAmount: totalAmount, treeUri: treeUri });
        emit EpochCreated(epochId, token, totalAmount, merkleRoot, treeUri);
    }

    /// @notice Claim rewards from a specific epoch.
    /// @param epochId   The epoch to claim from.
    /// @param amount    The reward amount for the caller, as encoded in the Merkle tree.
    /// @param proof     Merkle proof verifying the (caller, amount) leaf.
    function claim(uint256 epochId, uint256 amount, bytes32[] calldata proof)
        external nonReentrant whenNotPaused
    {
        require(!claimed[msg.sender][epochId], "Already claimed");

        Epoch memory epoch = epochs[epochId];
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, amount))));
        require(MerkleProof.verify(proof, epoch.merkleRoot, leaf), "Invalid proof");

        claimed[msg.sender][epochId] = true;
        IERC20(epoch.token).safeTransfer(msg.sender, amount);
        emit Claimed(msg.sender, epochId, epoch.token, amount);
    }
}
