// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

// Pool interfaces
interface ICLPoolActions {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

interface ICLPoolState {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            bool unlocked
        );
}

interface ICLSwapCallback {
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract DirectPoolSwap is ICLSwapCallback {
    address public constant pool = 0x7cfc2Da3ba598ef4De692905feDcA32565AB836E; // USDC/VELO pool address
    address public constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85; // USDC on Optimism
    address public constant VELO = 0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db; // VELO on Optimism

    address public admin;

    event SwapExecuted(address indexed user, uint256 amountIn, uint256 amountOut);

    constructor() {
        admin = msg.sender;
    }

    function _newAdmin(address newAdmin) external {
        require(msg.sender == admin, "Only owner can do this");
        admin = newAdmin;
    }

    function transferToAdmin(address Token) external {
        uint256 value = IERC20(Token).balanceOf(address(this));
        IERC20(Token).transfer(admin, value);
    }

    function V3SwapUSDCtoVelo() external {
        uint256 amountIn = IERC20(USDC).balanceOf(address(this));
        require(amountIn > 0, "Invalid input amount");

        // Get current sqrtPriceX96 from the pool
        (uint160 sqrtPriceX96, , , , , ) = ICLPoolState(pool).slot0();
        uint160 sqrtPriceLimitX96 = uint160(sqrtPriceX96 * 99 / 100); // 1% slippage

        // Ensure valid range
        if (sqrtPriceLimitX96 <= TickMath.MIN_SQRT_RATIO) {
            sqrtPriceLimitX96 = TickMath.MIN_SQRT_RATIO + 1;
        }

        // Approve pool to spend USDC
        IERC20(USDC).approve(pool, amountIn);

        // Prepare data for callback (not strictly needed here, but included for completeness)
        bytes memory data = abi.encode(address(this));

        // Call the pool's swap function
        ICLPoolActions(pool).swap(
            address(this),     // recipient
            true,              // zeroForOne: USDC -> VELO
            int256(amountIn),  // exact input
            sqrtPriceLimitX96, // price limit
            data               // callback data
        );
    }

    // This is the required callback for the pool to call after swap
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata /* data */
    ) external override {
        require(msg.sender == pool, "Callback only from pool");

        // If amount0Delta > 0, we must pay that amount of USDC to the pool
        if (amount0Delta > 0) {
            IERC20(USDC).transfer(pool, uint256(amount0Delta));
        }
        // If amount1Delta > 0, we must pay that amount of VELO to the pool (not expected in USDC->VELO swap)
        if (amount1Delta > 0) {
            IERC20(VELO).transfer(pool, uint256(amount1Delta));
        }
    }
}
