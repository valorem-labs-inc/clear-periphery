// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/External.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC1155TokenReceiver} from "solmate/tokens/ERC1155.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IValoremOptionsClearinghouse} from "valorem-core/interfaces/IValoremOptionsClearinghouse.sol";
import {ValoremOptionsClearinghouse} from "valorem-core/ValoremOptionsClearinghouse.sol";
import {ICashSettler} from "./interfaces/ICashSettler.sol";

/**
 * @title CashSettler.
 * @notice CashSettler is a contract that allows users to exercise options with cash settlement.
 */
contract CashSettler is ICashSettler, ERC1155TokenReceiver, IUniswapV3SwapCallback {
    /*//////////////////////////////////////////////////////////////
    //  Internal Data Structures
    //////////////////////////////////////////////////////////////*/

    /// @notice Payload for swap callback.
    struct SwapCallbackData {
        /// @custom:member caller The caller of the `exercise` function.
        address caller;
        /// @custom:member poolA The pool to swap from (i.e. MEME/WETH).
        IUniswapV3Pool poolA;
        /// @custom:member poolB The pool to swap to (i.e. WETH/USDC).
        IUniswapV3Pool poolB;
        /// @custom:member optionId Option Id assigned from ValoremOptionsClearinghouse.
        uint256 optionId;
        /// @custom:member optionsAmount The amount of options to exercise (i.e. 10).
        uint112 optionsAmount;
        /// @custom:member exerciseToken The token to use for exercising (i.e. MEME).
        ERC20 exerciseToken;
        /// @custom:member depth The depth of the swap.
        uint8 depth;
        /// @custom:member amountSurplus Minimum amount of surplus, if it is less, the call reverts.
        uint256 amountSurplus;
        /// @custom:member amountToRepaySwap2 Amount of tokens needed to be paid out after second swap.
        uint256 amountToRepaySwap2;
    }

    /*//////////////////////////////////////////////////////////////
    //  Tokens
    //////////////////////////////////////////////////////////////*/

    // TODO optimize storage layout, probably store these as IERC20Minimal
    /// @dev The address of WETH.
    ERC20 private immutable WETH;
    /// @dev The address of USDC.
    ERC20 private immutable USDC;

    /*//////////////////////////////////////////////////////////////
    //  Uniswap State
    //////////////////////////////////////////////////////////////*/

    /// @dev The address of WETH-USDC pool as ValoremOptionsClearinghouse is based on USDC.
    IUniswapV3Pool private immutable POOL_WETH_USDC;

    /*//////////////////////////////////////////////////////////////
    //  Uniswap Constants
    //////////////////////////////////////////////////////////////*/

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK).
    uint160 private constant MIN_SQRT_RATIO = 4295128739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK).
    uint160 private constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    /// @dev The ERC20 token transfer selector
    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    /*//////////////////////////////////////////////////////////////
    //  Valorem State
    //////////////////////////////////////////////////////////////*/

    /// @dev The address of ValoremOptionsClearinghouse.
    ValoremOptionsClearinghouse private immutable CLEARINGHOUSE;

    /*//////////////////////////////////////////////////////////////
    //  Constructor
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor.
     * @param _clearingHouse The address of ValoremOptionsClearinghouse.
     * @param _weth The address of WETH.
     * @param _usdc The address of USDC.
     * @param _poolWethUsdc The address of WETH-USDC pool.
     */
    constructor(ValoremOptionsClearinghouse _clearingHouse, ERC20 _weth, ERC20 _usdc, IUniswapV3Pool _poolWethUsdc) {
        // Approve ValoremOptionsClearinghouse to spend WETH
        SafeTransferLib.safeApprove(_weth, address(_clearingHouse), type(uint256).max);
        // Approve ValoremOptionsClearinghouse to spend USDC
        SafeTransferLib.safeApprove(_usdc, address(_clearingHouse), type(uint256).max);

        // Save state
        CLEARINGHOUSE = _clearingHouse;
        POOL_WETH_USDC = _poolWethUsdc;
        WETH = _weth;
        USDC = _usdc;
    }

    /*//////////////////////////////////////////////////////////////
    //  Modifiers
    //////////////////////////////////////////////////////////////*/

    modifier onlyValidOption(uint256 optionId) {
        // Check if option is Long, if not – revert
        if (CLEARINGHOUSE.tokenType(optionId) != IValoremOptionsClearinghouse.TokenType.Option) {
            revert OnlyLongsError(optionId);
        }

        _;
    }

    /*//////////////////////////////////////////////////////////////
    //  Exercising
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Exercise an option via 2-leg swap.
     * @param data The data for exercising an option.
     */
    function exercise2Leg(Exercise2LegData calldata data) external onlyValidOption(data.optionId) {
        // Transform the data into internal format

        // Approve a token to be spent by ValoremOptionsClearinghouse
        SafeTransferLib.safeApprove(ERC20(data.token), address(CLEARINGHOUSE), type(uint256).max);

        // Transfer options to this contract
        CLEARINGHOUSE.safeTransferFrom(msg.sender, address(this), data.optionId, data.optionsAmount, "");

        // Get the first pool that we will swap from
        IUniswapV3Pool poolA = data.optionType == OptionType.CALL ? data.poolToWeth : POOL_WETH_USDC;

        // Prepare Swap Callback Data
        bytes memory callbackData = abi.encode(
            SwapCallbackData({
                poolA: poolA,
                poolB: poolA == data.poolToWeth ? POOL_WETH_USDC : data.poolToWeth,
                optionId: data.optionId,
                optionsAmount: data.optionsAmount,
                depth: 0,
                exerciseToken: data.optionType == OptionType.CALL ? ERC20(data.token) : USDC,
                amountSurplus: data.amountSurplus,
                amountToRepaySwap2: 0,
                caller: msg.sender
            })
        );

        // Determine tick direction for `poolA`
        bool zeroForOne = poolA.token0() != address(WETH);

        // Initiate the first swap
        poolA.swap({
            recipient: address(this),
            zeroForOne: zeroForOne,
            amountSpecified: -1 * int256(data.amount),
            sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1,
            data: callbackData
        });

        if (data.optionType == OptionType.CALL) {
            emit Call(msg.sender, data.optionId, data.optionsAmount);
        } else {
            emit Put(msg.sender, data.optionId, data.optionsAmount);
        }
    }

    /*//////////////////////////////////////////////////////////////
    //  Uniswap V3 Callback
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        // Decode callback data
        SwapCallbackData memory decoded = abi.decode(data, (SwapCallbackData));

        // Determine tick direction for `poolB`
        bool zeroForOne = decoded.poolB.token0() == address(WETH);

        if (decoded.depth == 0) {
            // If a caller is not a correct pool, revert
            if (msg.sender != address(decoded.poolA)) {
                revert UnauthorizedError();
            }

            // Increment depth as we are going to make another swap
            decoded.depth++;
            // Save amount out from the first swap to be paid out later
            decoded.amountToRepaySwap2 = uint256(amount0Delta);

            // Initiate the second swap
            decoded.poolB.swap({
                recipient: address(this),
                zeroForOne: zeroForOne,
                amountSpecified: -amount1Delta,
                sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1,
                data: abi.encode(decoded)
            });
        } else if (decoded.depth == 1) {
            // If a caller is not a correct pool, revert
            if (msg.sender != address(decoded.poolB)) {
                revert UnauthorizedError();
            }

            // Repay to the second swap straight away
            SafeTransferLib.safeTransfer(
                WETH, address(decoded.poolB), zeroForOne ? uint256(amount0Delta) : uint256(amount1Delta)
            );

            // Exercise options on the ValoremOptionsClearinghouse
            CLEARINGHOUSE.exercise(decoded.optionId, decoded.optionsAmount);

            // Repay to the first swap
            SafeTransferLib.safeTransfer(
                decoded.exerciseToken, address(decoded.poolA), decoded.amountToRepaySwap2
            );

            // Check if the exercise is profitable and revert if not
            require(decoded.amountSurplus <= USDC.balanceOf(address(this)), "Not profitable");

            // Pay the profits out
            // TODO see if we can not do the balance call and instead just know the amount from the swap2 callback
            SafeTransferLib.safeTransfer(USDC, address(decoded.caller), USDC.balanceOf(address(this)));
        } else {
            revert InvalidDepthError(decoded.depth);
        }
    }

    /*//////////////////////////////////////////////////////////////
    //  ERC155 Overrides
    //////////////////////////////////////////////////////////////*/

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return ERC1155TokenReceiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
    }
}
