// SPDX-License-Identifier: MPL-2.0
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OwnableOperators } from "./OwnableOperators.sol";
import { ISwapRouter, IUniswapV3Pool } from "./interfaces/IUniswapV3.sol";
import { Swapper } from "./Swapper.sol";

/// @notice Deploys ephemeral Swapper contracts to generate synthetic trading volume
///         on a single Uniswap V3 pool. Swap output is returned to this contract,
///         allowing the operator to alternate swap direction each run.
contract Pulsar is OwnableOperators {
    using SafeERC20 for IERC20;

    ISwapRouter    public immutable swapRouter;
    IUniswapV3Pool public pool;

    event PoolSet(address pool);
    event Pulsed(address[] swappers, bool zeroForOne, uint256 amountEach);

    constructor(address _swapRouter, address _owner) OwnableOperators(_owner) {
        swapRouter = ISwapRouter(_swapRouter);
    }

    function setPool(address _pool) external onlyOperator {
        pool = IUniswapV3Pool(_pool);
        emit PoolSet(_pool);
    }

    /// @param totalAmount     Total tokenIn (wei) to distribute across swappers.
    /// @param amountPerSwapper Tokens (wei) allocated to each Swapper.
    /// @param zeroForOne      True to swap token0 → token1; false for the reverse.
    /// @param slippageBps     Maximum acceptable slippage in basis points (e.g. 50 = 0.5%).
    function pulse(
        uint256 totalAmount,
        uint256 amountPerSwapper,
        bool    zeroForOne,
        uint256 slippageBps
    ) external onlyOperator returns (address[] memory swappers) {
        require(amountPerSwapper > 0, "amountPerSwapper must be > 0");
        uint256 numSwappers = totalAmount / amountPerSwapper;
        require(numSwappers > 0, "totalAmount too small");
        require(address(pool) != address(0), "pool not set");

        IERC20 tokenIn  = zeroForOne ? IERC20(pool.token0()) : IERC20(pool.token1());
        IERC20 tokenOut = zeroForOne ? IERC20(pool.token1()) : IERC20(pool.token0());
        uint24 fee      = pool.fee();

        swappers = new address[](numSwappers);
        for (uint256 i = 0; i < numSwappers; i++) {
            Swapper s = new Swapper(
                address(swapRouter),
                address(pool),
                address(tokenIn),
                address(tokenOut),
                fee,
                address(this),
                slippageBps
            );
            tokenIn.safeTransfer(address(s), amountPerSwapper);
            swappers[i] = address(s);
        }

        emit Pulsed(swappers, zeroForOne, amountPerSwapper);
    }
}
