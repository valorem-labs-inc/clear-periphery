// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC20,IUniswapV3Pool} from "./External.sol";

/**
 * @title ICashSettler.
 * @notice Interface for CashSettler.
 */
interface ICashSettler {
    /**
     * @notice Thrown if trying to exercise short.
     * @param optionId The option id that was not exercised.
     */
    error OnlyLongsError(uint256 optionId);
    /**
     * @notice Thrown if trying to call Uniswap V3 Callback not
     * from the pool.
     */
    error UnauthorizedError();
    /**
     * @notice Thrown if depth passed in Uniswap V3 Callback is
     * incorrect.
     * @param depth Incorrect depth.
     */
    error InvalidDepthError(uint256 depth);

    /**
     * @notice Emitted when an call option is exercised.
     * @param sender The address that initiated the exercise.
     * @param optionId The option id that was exercised.
     * @param amount The amount of options that were exercised.
     */
    event Call(address indexed sender, uint256 indexed optionId, uint256 amount);
    /**
     * @notice Emitted when a put option is exercised.
     * @param sender The address that initiated the exercise.
     * @param optionId The option id that was exercised.
     * @param amount The amount of options that were exercised.
     */
    event Put(address indexed sender, uint256 indexed optionId, uint256 amount);

    // @notice Option type.
    enum OptionType {CALL, PUT}

    /// @notice Payload for exercising an option via 2-leg swap.
    struct Exercise2LegData {
        /// @custom:member optionType Type of the option.
        OptionType optionType;
        /// @custom:member optionId The option id to exercise.
        uint256 optionId;
        /// @custom:member optionsAmount The amount of options to exercise (i.e. 10).
        uint112 optionsAmount;
        /// @custom:member token The token to exercise (i.e. MEME).
        IERC20 token;
        /// @custom:member amount The amount of tokens to exercise (i.e. 10e9 MEME).
        uint256 amount;
        /// @custom:member amountSurplus The minimum amount of USDC to receive.
        uint256 amountSurplus;
        /// @custom:member poolToWeth The pool to swap from (i.e. MEME/WETH).
        IUniswapV3Pool poolToWeth;
    }
}
