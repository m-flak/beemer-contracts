// SPDX-License-Identifier: MPL-2.0
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISwapRouter, IUniswapV3Pool } from "./interfaces/IUniswapV3.sol";

/// @dev Ephemeral contract deployed by FeeFarm. Receives tokenIn at construction,
///      executes a single Uniswap V3 swap, and sends the output back to the fee farm.
contract Swapper {
    using SafeERC20 for IERC20;

    uint256 private constant Q96 = 2 ** 96;

    ISwapRouter public immutable router;
    IUniswapV3Pool public immutable pool;
    IERC20 public immutable tokenIn;
    IERC20 public immutable tokenOut;
    uint24 public immutable poolFee;
    address public immutable feeFarm;
    uint256 public immutable slippageBps;

    constructor(
        address _router,
        address _pool,
        address _tokenIn,
        address _tokenOut,
        uint24 _poolFee,
        address _feeFarm,
        uint256 _slippageBps
    ) {
        router = ISwapRouter(_router);
        pool = IUniswapV3Pool(_pool);
        tokenIn = IERC20(_tokenIn);
        tokenOut = IERC20(_tokenOut);
        poolFee = _poolFee;
        feeFarm = _feeFarm;
        slippageBps = _slippageBps;
    }

    function execute() external {
        uint256 amountIn = tokenIn.balanceOf(address(this));

        // Query pool spot price. sqrtPriceX96 = sqrt(token1/token0) * 2^96.
        // Split into two sequential muls to keep intermediate values within uint256.
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint256 sq = uint256(sqrtPriceX96);

        uint256 amountOutExpected;
        if (address(tokenIn) < address(tokenOut)) {
            // zeroForOne: price = sq^2 / Q96^2, expectedOut = amountIn * sq / Q96 * sq / Q96
            amountOutExpected = (amountIn * sq / Q96) * sq / Q96;
        } else {
            // oneForZero: price = Q96^2 / sq^2, expectedOut = amountIn * Q96 / sq * Q96 / sq
            amountOutExpected = (amountIn * Q96 / sq) * Q96 / sq;
        }

        uint256 amountOutMinimum = amountOutExpected * (10_000 - slippageBps) / 10_000;

        tokenIn.forceApprove(address(router), amountIn);
        router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(tokenIn),
                tokenOut: address(tokenOut),
                fee: poolFee,
                recipient: feeFarm,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            })
        );
    }
}
