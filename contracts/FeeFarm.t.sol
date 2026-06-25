// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { FeeFarm } from "./FeeFarm.sol";

// ── Mocks ────────────────────────────────────────────────────────────────────

contract MockPool {
    address public token0;
    address public token1;
    uint24  public fee;

    constructor(address _t0, address _t1, uint24 _fee) {
        token0 = _t0; token1 = _t1; fee = _fee;
    }
}

contract MockFactory {
    mapping(bytes32 => address) private _pools;

    function setPool(address t0, address t1, uint24 fee, address pool) external {
        _pools[keccak256(abi.encodePacked(t0, t1, fee))] = pool;
    }

    function getPool(address t0, address t1, uint24 fee) external view returns (address) {
        return _pools[keccak256(abi.encodePacked(t0, t1, fee))];
    }
}

contract MockPositionManager {
    struct PositionData { address token0; address token1; uint24 fee; }
    mapping(uint256 => PositionData) private _pos;

    function setPosition(uint256 tokenId, address t0, address t1, uint24 fee) external {
        _pos[tokenId] = PositionData(t0, t1, fee);
    }

    /// @dev Simulates the NFT manager calling onERC721Received on FeeFarm.
    function mintTo(address feeFarm, uint256 tokenId) external {
        IERC721Receiver(feeFarm).onERC721Received(address(this), msg.sender, tokenId, "");
    }

    function positions(uint256 tokenId) external view returns (
        uint96, address, address token0, address token1,
        uint24 fee, int24, int24, uint128, uint256, uint256, uint128, uint128
    ) {
        PositionData memory p = _pos[tokenId];
        return (0, address(0), p.token0, p.token1, p.fee, 0, 0, 0, 0, 0, 0, 0);
    }

    function safeTransferFrom(address, address, uint256) external {}
}

// ── Tests ─────────────────────────────────────────────────────────────────────

contract FeeFarmTest is Test {
    FeeFarm              feeFarm;
    MockFactory          mockFactory;
    MockPositionManager  npm;
    MockPool             pool;

    address owner     = makeAddr("owner");
    address recipient = makeAddr("recipient");
    address token0;
    address token1;

    uint256 constant ID_A = 1;
    uint256 constant ID_B = 2;
    uint256 constant ID_C = 3;

    bytes32 ppKey;

    function setUp() public {
        token0 = makeAddr("token0");
        token1 = makeAddr("token1");
        if (uint160(token0) > uint160(token1)) (token0, token1) = (token1, token0);

        npm         = new MockPositionManager();
        pool        = new MockPool(token0, token1, 3000);
        mockFactory = new MockFactory();
        mockFactory.setPool(token0, token1, 3000, address(pool));
        feeFarm = new FeeFarm(address(npm), address(mockFactory), address(0), owner);
        ppKey   = keccak256(abi.encodePacked(token0, token1, uint24(3000)));

        vm.prank(owner);
        feeFarm.addPool(address(pool));

        npm.setPosition(ID_A, token0, token1, 3000);
        npm.setPosition(ID_B, token0, token1, 3000);
        npm.setPosition(ID_C, token0, token1, 3000);

        npm.mintTo(address(feeFarm), ID_A);
        npm.mintTo(address(feeFarm), ID_B);
        npm.mintTo(address(feeFarm), ID_C);
    }

    function test_RescuePosition_SwapAndPopPreservesArray() public {
        // Initial state: [ID_A, ID_B, ID_C]
        FeeFarm.PoolPosition memory before = feeFarm.getPoolPosition(ppKey);
        assertEq(before.positionTokenIds.length, 3);

        // Remove the middle element. Swap-and-pop moves ID_C into index 1.
        // Expected result: [ID_A, ID_C]
        vm.expectCall(
            address(npm),
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", address(feeFarm), recipient, ID_B)
        );
        vm.prank(owner);
        feeFarm.rescuePosition(ID_B, recipient);

        FeeFarm.PoolPosition memory after_ = feeFarm.getPoolPosition(ppKey);
        assertEq(after_.positionTokenIds.length, 2);
        assertEq(after_.positionTokenIds[0], ID_A);
        assertEq(after_.positionTokenIds[1], ID_C);
    }

    function test_RescuePosition_RevertsWhenNotTracked() public {
        vm.prank(owner);
        vm.expectRevert("Position not tracked");
        feeFarm.rescuePosition(999, recipient);
    }
}
