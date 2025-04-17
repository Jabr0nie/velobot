// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Velodrome Slipstream Pool Interface (from provided ICLPoolActions)
interface ICLPoolActions {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

contract DirectPoolSwap {
    using SafeERC20 for IERC20;

    address public immutable pool; // USDC/VELO pool address
    address public constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85; // USDC on Optimism
    address public constant VELO = 0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db; // VELO on Optimism
    bool public immutable zeroForOne; // True if USDC is token0, false if VELO is token0

    // Event to log swaps
    event SwapExecuted(address indexed user, uint256 amountIn, uint256 amountOut);

    constructor(address _pool, bool _zeroForOne) {
        pool = _pool;
        zeroForOne = _zeroForOne;
    }

    /// @notice Swaps a fixed amount of USDC for VELO directly with the pool
    /// @param amountIn The amount of USDC to swap
    /// @param amountOutMinimum The minimum amount of VELO to receive
    /// @param deadline The timestamp after which the transaction will revert
    /// @param sqrtPriceLimitX96 The price limit for the swap (0 for no limit)
    /// @return amountOut The amount of VELO received
    function swapExactInputSingle(
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut) {
        // Ensure deadline is in the future
        require(deadline >= block.timestamp, "Swap deadline expired");
        require(amountIn > 0, "Invalid input amount");

        // Transfer USDC to this contract
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amountIn);

      IERC20(USDC).approve(pool, amountIn);

        // Prepare swap data to pass to callback
        bytes memory data = abi.encode(msg.sender, amountOutMinimum);

        // Call the pool's swap function
        (int256 amount0, int256 amount1) = ICLPoolActions(pool).swap(
            address(this), // Recipient of output tokens (this contract)
            zeroForOne, // Direction of swap (USDC -> VELO or VELO -> USDC)
            int256(amountIn), // Positive for exact input
            sqrtPriceLimitX96, // Price limit (0 for no limit)
            data // Pass data to callback
        );

        // Calculate amountOut based on token order
        amountOut = zeroForOne ? uint256(-amount1) : uint256(-amount0);

        // Ensure minimum output is met
        require(amountOut >= amountOutMinimum, "Insufficient output amount");

        // Transfer VELO to the caller
        IERC20(VELO).safeTransfer(msg.sender, amountOut);

        // Emit event
        emit SwapExecuted(msg.sender, amountIn, amountOut);

        return amountOut;
    }

    /// @notice Callback function called by the pool during the swap
    /// @param amount0Delta The change in token0 balance (negative if we pay, positive if we receive)
    /// @param amount1Delta The change in token1 balance (negative if we pay, positive if we receive)
    /// @param data Data passed from the swap call
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        // Verify the caller is the pool
        require(msg.sender == pool, "Invalid caller");

        // Decode data
        (address recipient, uint256 amountOutMinimum) = abi.decode(data, (address, uint256));

        // Determine input and output amounts
        uint256 amountToPay;
        address tokenToPay;

        if (zeroForOne) {
            // USDC -> VELO: We pay token0 (USDC), receive token1 (VELO)
            require(amount0Delta > 0, "Invalid amount0Delta");
            require(amount1Delta < 0, "Invalid amount1Delta");
            amountToPay = uint256(amount0Delta);
            tokenToPay = USDC;
        } else {
            // VELO -> USDC: We pay token1 (VELO), receive token0 (USDC)
            require(amount1Delta > 0, "Invalid amount1Delta");
            require(amount0Delta < 0, "Invalid amount0Delta");
            amountToPay = uint256(amount1Delta);
            tokenToPay = VELO;
        }

        // Transfer the input tokens to the pool
        IERC20(tokenToPay).safeTransfer(pool, amountToPay);
    }
}