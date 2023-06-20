// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// TODO rename and minify where possible

interface IERC20Minimal {}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IUniswapV3Pool {
    function token0() external returns (address);
    function token1() external returns (address);
    function fee() external view returns (uint24);
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

interface IUniswapV3SwapCallback {
    /// @notice Called to `msg.sender` after executing a swap via IUniswapV3Pool#swap.
    /// @dev In the implementation you must pay the pool tokens owed for the swap.
    /// The caller of this method must be checked to be a UniswapV3Pool deployed by the canonical UniswapV3Factory.
    /// amount0Delta and amount1Delta can both be 0 if no tokens were swapped.
    /// @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token0 to the pool.
    /// @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token1 to the pool.
    /// @param data Any data passed through by the caller via the IUniswapV3PoolActions#swap call
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;
}

// library PoolAddress {
//     bytes32 internal constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

//     struct PoolKey {
//         address token0;
//         address token1;
//         uint24 fee;
//     }

//     function getPoolKey(address tokenA, address tokenB, uint24 fee) internal pure returns (PoolKey memory) {
//         if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
//         return PoolKey({token0: tokenA, token1: tokenB, fee: fee});
//     }

//     function computeAddress(address factory, PoolKey memory key) internal pure returns (address pool) {
//         require(key.token0 < key.token1);
//         pool = address(
//             uint160(
//                 uint256(
//                     keccak256(
//                         abi.encodePacked(
//                             hex"ff",
//                             factory,
//                             keccak256(abi.encode(key.token0, key.token1, key.fee)),
//                             POOL_INIT_CODE_HASH
//                         )
//                     )
//                 )
//             )
//         );
//     }
// }
