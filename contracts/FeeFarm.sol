// SPDX-License-Identifier: MPL-2.0
pragma solidity ^0.8.28;

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OwnableOperators } from "./OwnableOperators.sol";
import { INonfungiblePositionManager, IUniswapV3Factory, IUniswapV3Pool } from "./interfaces/IUniswapV3.sol";

contract FeeFarm is IERC721Receiver, OwnableOperators {
    using SafeERC20 for IERC20;

    struct PoolPosition {
        address pool;
        address token0;
        address token1;
        uint24 poolFee;
        uint256 totalCollected0;
        uint256 totalCollected1;
        uint256[] positionTokenIds;
    }

    mapping(bytes32 => PoolPosition) private poolPositions;
    bytes32[] private ppIds;

    INonfungiblePositionManager public immutable positionManager;
    IUniswapV3Factory public immutable factory;
    address public immutable feeVault;

    event PoolAdded(bytes32 indexed ppKey, address pool, address token0, address token1, uint24 fee);
    event PositionReceived(bytes32 indexed ppKey, address token0, address token1, uint256 positionId);
    event PositionRescued(bytes32 indexed ppKey, uint256 tokenId, address recipient);
    event FeesCollected(bytes32 indexed ppKey, uint256 amount0, uint256 amount1);

    constructor(address _positionManager, address _factory, address _feeVault, address _owner) OwnableOperators(_owner) {
        positionManager = INonfungiblePositionManager(_positionManager);
        factory = IUniswapV3Factory(_factory);
        feeVault = _feeVault;
    }

    /// @notice Registers a pool. Replaces the pool address for an existing (pair, fee) key without clearing history.
    function addPool(address _pool) external onlyOperator {
        address _token0 = IUniswapV3Pool(_pool).token0();
        address _token1 = IUniswapV3Pool(_pool).token1();
        uint24 _poolFee = IUniswapV3Pool(_pool).fee();

        bytes32 ppKey = keccak256(abi.encodePacked(_token0, _token1, _poolFee));

        // Only track the key once; updating an existing pair reuses the same slot.
        if (poolPositions[ppKey].pool == address(0)) ppIds.push(ppKey);

        PoolPosition storage pos = poolPositions[ppKey];
        pos.pool = _pool;
        pos.token0 = _token0;
        pos.token1 = _token1;
        pos.poolFee = _poolFee;

        emit PoolAdded(ppKey, _pool, _token0, _token1, _poolFee);
    }

    /// @dev Called by the NFT contract when an LP position NFT is transferred to this contract.
    ///      The matching pool must have been registered via addPool first.
    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        require(msg.sender == address(positionManager), "Only NonfungiblePositionManager");

        (, , address _token0, address _token1, uint24 _fee, , , , , , , ) = positionManager.positions(_tokenId);

        bytes32 ppKey = keccak256(abi.encodePacked(_token0, _token1, _fee));
        require(
            poolPositions[ppKey].pool == factory.getPool(_token0, _token1, _fee),
            "Pool not registered"
        );

        poolPositions[ppKey].positionTokenIds.push(_tokenId);

        emit PositionReceived(ppKey, _token0, _token1, _tokenId);
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @notice Collects all accrued fees across every position in a pool into this contract.
    /// @param ppKey The pool key returned by keccak256(abi.encodePacked(token0, token1)).
    function collect(bytes32 ppKey) external onlyOperator returns (uint256 amount0, uint256 amount1) {
        PoolPosition storage pos = poolPositions[ppKey];
        require(pos.pool != address(0), "Pool not registered");

        for (uint256 i = 0; i < pos.positionTokenIds.length; i++) {
            (uint256 a0, uint256 a1) = positionManager.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: pos.positionTokenIds[i],
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
            amount0 += a0;
            amount1 += a1;
        }

        pos.totalCollected0 += amount0;
        pos.totalCollected1 += amount1;

        if (amount0 > 0) IERC20(pos.token0).safeTransfer(feeVault, amount0);
        if (amount1 > 0) IERC20(pos.token1).safeTransfer(feeVault, amount1);

        if (amount0 > 0 || amount1 > 0) emit FeesCollected(ppKey, amount0, amount1);
    }

    /// @notice Removes a tracked LP NFT from this contract and safe-transfers it to `recipient`.
    ///         Use to recover an LP position that was transferred here but is no longer needed.
    /// @param tokenId The Uniswap V3 LP NFT token ID to recover.
    /// @param recipient The address to receive the NFT.
    function rescuePosition(uint256 tokenId, address recipient) external onlyOperator {
        (, , address _token0, address _token1, uint24 _fee, , , , , , , ) = positionManager.positions(tokenId);
        bytes32 ppKey = keccak256(abi.encodePacked(_token0, _token1, _fee));

        uint256[] storage ids = poolPositions[ppKey].positionTokenIds;
        bool found = false;
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] == tokenId) {
                ids[i] = ids[ids.length - 1];
                ids.pop();
                found = true;
                break;
            }
        }
        require(found, "Position not tracked");

        emit PositionRescued(ppKey, tokenId, recipient);
        positionManager.safeTransferFrom(address(this), recipient, tokenId);
    }

    /// @notice Returns the pool position data for a given key.
    function getPoolPosition(bytes32 ppKey) external view returns (PoolPosition memory) {
        return poolPositions[ppKey];
    }

    /// @notice Returns all registered pool keys.
    function getPoolKeys() external view returns (bytes32[] memory) {
        return ppIds;
    }
}