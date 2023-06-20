// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC20,IUniswapV3Pool} from "./External.sol";

/**
 * @title ICashSettler
 * @notice Interface for CashSettler
 */
interface ICashSettler {
    /**
     * @notice Throws if trying to exercise short
     * @param optionId The option id that was not exercised
     */
    error OnlyLongs(uint256 optionId);

    /**
     * @notice Emitted when an call option is exercised
     * @param sender The address that initiated the exercise
     * @param optionId The option id that was exercised
     * @param amount The amount of options that were exercised
     */
    event Call(address indexed sender, uint256 indexed optionId, uint256 amount);
    /**
     * @notice Emitted when a put option is exercised
     * @param sender The address that initiated the exercise
     * @param optionId The option id that was exercised
     * @param amount The amount of options that were exercised
     */
    event Put(address indexed sender, uint256 indexed optionId, uint256 amount);

    // @notice Option type
    enum OptionType {CALL, PUT}

    /**
     * @notice Payload for exercising an option via 2-leg swap
     * @param optionType Type of the option
     * @param optionsId Option Id assigned from ClearingHouse
     * @param optionsAmount The amount of options to exercise (i.e. 10)
     * @param token The token to use for exercising (i.e. MEME)
     * @param amount The amount of tokens to exercise (i.e. 10e9 MEME)
     * @param amountSurplus The minimum amount of USDC to receive
     * @param poolToWeth The pool to swap from (i.e. MEME/WETH)
     */
    struct Exercise2LegData {
        OptionType optionType;
        uint256 optionId;
        uint112 optionsAmount;
        IERC20 token;
        uint256 amount;
        uint256 amountSurplus;
        IUniswapV3Pool poolToWeth;
    }
}
