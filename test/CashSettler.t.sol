// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {StdStyle} from "forge-std/StdStyle.sol";
import {CashSettler, ICashSettler} from "../src/CashSettler.sol";
import {IValoremOptionsClearinghouse} from "valorem-core/interfaces/IValoremOptionsClearinghouse.sol";
import {ValoremOptionsClearinghouse} from "valorem-core/ValoremOptionsClearinghouse.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC20, IUniswapV3Pool} from "../src/interfaces/External.sol";

interface IQuoter {
    function quoteExactInput(bytes calldata path, uint256 amountIn) external returns (uint256 amountOut);
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
    function quoteExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountOut,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountIn);
}

/// @notice inspired by memes
contract CashSettlerTest is Test {
    // contracts
    ValoremOptionsClearinghouse private clearingHouse;
    CashSettler private vault;
    IQuoter private constant quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

    // assets
    ERC20 private memecoin;
    ERC20 private stablecoin;
    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant PEPE = IERC20(0x6982508145454Ce325dDbE47a25d4ec3d2311933);
    IERC20 private constant LINK = IERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);

    IUniswapV3Pool private constant POOL_USDC_WETH = IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
    uint24 private constant POOL_USDC_FEE = 500;
    // Abitrum -- 0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443
    // Optimism -- 0x85149247691df622eaF1a8Bd0CaFd40BC45154a9

    IUniswapV3Pool private constant POOL_PEPE_WETH = IUniswapV3Pool(0x11950d141EcB863F01007AdD7D1A342041227b58);
    uint24 private constant POOL_PEPE_FEE = 3_000;

    IUniswapV3Pool private constant POOL_LINK_WETH = IUniswapV3Pool(0xa6Cc3C2531FdaA6Ae1A3CA84c2855806728693e8); // LINK is token0
    uint24 private constant POOL_LINK_FEE = 3_000;

    // starting balances
    uint256 private constant initialMEMEBalance = 1_000_000e18;
    uint256 private constant initialStableBalance = 1_000_000e9;
    uint256 private constant initialUSDCBalance = 1_000_000e6;

    // option types
    uint256 private itmcall;
    uint256 private atmcall;
    uint256 private otmcall;
    uint256 private otmput;
    uint256 private atmput;
    uint256 private itmput;
    uint256 private callOption;
    uint256 private putOption;
    uint256[] private memechain;

    // accounts
    address private constant me = address(0xDADA);
    address private constant you = address(0xFEEB);
    address private constant admin = address(0xBEBE);

    // timestamps
    uint40 private constant today = 1683647818;
    uint40 private constant exercise = 1683921600;
    uint40 private constant expiry = 1684526400;

    // divisors
    uint16 private constant DIVISOR_BPS = 10_000;
    uint24 private constant DIVISOR_HUNDREDTHS_OF_BPS = 1_000_000;

    // Duplicated events from the interface
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

    // Duplicated internal struct from the contract
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
        IERC20 exerciseToken;
        /// @custom:member depth The depth of the swap.
        uint8 depth;
        /// @custom:member amountSurplus Minimum amount of surplus, if it is less, the call reverts.
        uint256 amountSurplus;
        /// @custom:member amountToRepaySwap2 Amount of tokens needed to be paid out after second swap.
        uint256 amountToRepaySwap2;
    }

    function setUp() public {
        // fork mainnet and warp to now
        vm.createSelectFork(vm.envString("RPC_URL"), 17381236); // 17274287, 17344069
        vm.warp(today);

        // deploy infrastructure
        clearingHouse = new ValoremOptionsClearinghouse(admin, address(0xCACA));

        // deploy memetics // TODO replace with PEPE and USDC everywhere
        // memecoin = new Memecoin();
        // Memecoin(address(memecoin)).mint(address(this), initialMEMEBalance);
        memecoin = ERC20(address(PEPE));
        deal(address(memecoin), address(this), initialMEMEBalance);
        stablecoin = new Stablecoin();
        Stablecoin(address(stablecoin)).mint(address(this), initialStableBalance);

        // deal balances
        deal(address(memecoin), me, initialMEMEBalance);
        deal(address(stablecoin), me, initialStableBalance);
        deal(address(memecoin), you, initialMEMEBalance);
        deal(address(stablecoin), you, initialStableBalance);
        deal(address(PEPE), me, initialMEMEBalance);
        deal(address(LINK), me, initialMEMEBalance);
        deal(address(USDC), me, initialUSDCBalance);
        deal(address(PEPE), you, initialMEMEBalance);
        deal(address(LINK), you, initialMEMEBalance);
        deal(address(USDC), you, initialUSDCBalance);
        vm.deal(you, 100 ether);
        startHoax(me, 100 ether);
        // deploy option chains
        itmcall = clearingHouse.newOptionType({
            underlyingAsset: address(memecoin),
            underlyingAmount: 1e6,
            exerciseAsset: address(stablecoin),
            exerciseAmount: 415e9,
            exerciseTimestamp: exercise,
            expiryTimestamp: expiry
        });
        memechain.push(itmcall);
        atmcall = clearingHouse.newOptionType({
            underlyingAsset: address(memecoin),
            underlyingAmount: 1e6,
            exerciseAsset: address(stablecoin),
            exerciseAmount: 420e9,
            exerciseTimestamp: exercise,
            expiryTimestamp: expiry
        });
        memechain.push(atmcall);
        otmcall = clearingHouse.newOptionType({
            underlyingAsset: address(memecoin),
            underlyingAmount: 1e6,
            exerciseAsset: address(stablecoin),
            exerciseAmount: 425e9,
            exerciseTimestamp: exercise,
            expiryTimestamp: expiry
        });
        memechain.push(otmcall);
        otmput = clearingHouse.newOptionType({
            underlyingAsset: address(stablecoin),
            underlyingAmount: 415e9,
            exerciseAsset: address(memecoin),
            exerciseAmount: 1e6,
            exerciseTimestamp: exercise,
            expiryTimestamp: expiry
        });
        memechain.push(otmput);
        atmput = clearingHouse.newOptionType({
            underlyingAsset: address(stablecoin),
            underlyingAmount: 420e9,
            exerciseAsset: address(memecoin),
            exerciseAmount: 1e6,
            exerciseTimestamp: exercise,
            expiryTimestamp: expiry
        });
        memechain.push(atmput);
        itmput = clearingHouse.newOptionType({
            underlyingAsset: address(stablecoin),
            underlyingAmount: 425e9,
            exerciseAsset: address(memecoin),
            exerciseAmount: 1e6,
            exerciseTimestamp: exercise,
            expiryTimestamp: expiry
        });
        memechain.push(itmput);
        vault = new CashSettler(clearingHouse, WETH, USDC, POOL_USDC_WETH);
    }

    ////####////####////####////####////####////####////
    ////####////####    Test Helpers    ####////####////
    ////####////####////####////####////####////####////

    modifier withCallAtStrike(address volatileAsset, uint96 strike) {
        callOption = clearingHouse.newOptionType({
            underlyingAsset: volatileAsset,
            underlyingAmount: 1e18,
            exerciseAsset: address(USDC),
            exerciseAmount: strike,
            exerciseTimestamp: exercise,
            expiryTimestamp: expiry
        });

        _;
    }

    modifier withPutAtStrike(address volatileAsset, uint96 strike) {
        putOption = clearingHouse.newOptionType({
            underlyingAsset: address(USDC),
            underlyingAmount: strike,
            exerciseAsset: volatileAsset,
            exerciseAmount: 1e18,
            exerciseTimestamp: exercise,
            expiryTimestamp: expiry
        });

        _;
    }

    function _valoremFee(uint256 amount) private view returns (uint256) {
        return (amount * clearingHouse.feeBps()) / DIVISOR_BPS;
    }

    function _uniswapFees(uint256 amount, uint24 feeInHundredthsOfBips) private pure returns (uint256) {
        return (amount * feeInHundredthsOfBips) / DIVISOR_HUNDREDTHS_OF_BPS;
    }

    function testRevert_exercise2Leg_whenNotLong() public {
        memecoin.approve(address(clearingHouse), type(uint256).max);
        clearingHouse.setApprovalForAll(address(vault), true);
        uint256 short = clearingHouse.write(itmcall, 100);

        vm.expectRevert(abi.encodeWithSelector(ICashSettler.OnlyLongsError.selector, short));
        vault.exercise2Leg(
            ICashSettler.Exercise2LegData({
                optionType: ICashSettler.OptionType.CALL,
                optionId: short,
                optionsAmount: 0,
                amount: 0,
                token: IERC20(address(0)),
                amountSurplus: 0,
                poolToWeth: IUniswapV3Pool(address(0))
            })
        );
    }

    // function testRevert_exercise2Leg_whenOptionExpired() public {
    //     memecoin.approve(address(clearingHouse), type(uint256).max);
    //     clearingHouse.setApprovalForAll(address(factory), true);
    //     clearingHouse.write(itmcall, 100);
    //
    //     vm.warp(expiry);
    //
    //     vm.expectRevert(abi.encodeWithSelector(MemevaultFactory.CannotMemeExpiredOption.selector, itmcall));
    //     factory.create(itmcall, address(memecoin), POOL_PEPE_WETH, 100);
    // }

    function testRevert_exercise2Leg_whenDontHoldSufficientLongs() public {
        memecoin.approve(address(clearingHouse), type(uint256).max);
        clearingHouse.setApprovalForAll(address(vault), true);

        clearingHouse.write(itmcall, 50);

        vm.expectRevert(stdError.arithmeticError);

        vault.exercise2Leg(
            ICashSettler.Exercise2LegData({
                optionType: ICashSettler.OptionType.CALL,
                optionsAmount: 51,
                optionId: itmcall,
                amount: 0,
                token: IERC20(address(memecoin)),
                amountSurplus: 0,
                poolToWeth: POOL_PEPE_WETH
            })
        );
    }

    function testRevert_uniswapV3SwapCallback_whenCalledNotFromPool() public {
        memecoin.approve(address(clearingHouse), type(uint256).max);
        clearingHouse.setApprovalForAll(address(vault), true);

        vm.expectRevert(abi.encodeWithSelector(ICashSettler.UnauthorizedError.selector));
        bytes memory data = abi.encode(
            SwapCallbackData({
                caller: address(0),
                poolA: POOL_USDC_WETH,
                poolB: POOL_PEPE_WETH,
                optionId: 0,
                optionsAmount: 0,
                exerciseToken: IERC20(address(0)),
                depth: 0,
                amountSurplus: 0,
                amountToRepaySwap2: 0
            })
        );

        vault.uniswapV3SwapCallback(2, 2, data);
    }

    function testRevert_uniswapV3SwapCallback_whenDepthIsInvalid() public {
        memecoin.approve(address(clearingHouse), type(uint256).max);
        clearingHouse.setApprovalForAll(address(vault), true);

        vm.expectRevert(abi.encodeWithSelector(ICashSettler.InvalidDepthError.selector, 2));
        bytes memory data = abi.encode(
            SwapCallbackData({
                caller: address(0),
                poolA: POOL_USDC_WETH,
                poolB: POOL_PEPE_WETH,
                optionId: 0,
                optionsAmount: 0,
                exerciseToken: IERC20(address(0)),
                depth: 2,
                amountSurplus: 0,
                amountToRepaySwap2: 0
            })
        );

        vault.uniswapV3SwapCallback(2, 2, data);
    }

    function testRevert_exercise2Leg_whenHoldWrongTypeOfLongs() public {
        memecoin.approve(address(clearingHouse), type(uint256).max);
        clearingHouse.setApprovalForAll(address(vault), true);

        clearingHouse.write(atmcall, 50);

        vm.expectRevert(stdError.arithmeticError);

        vault.exercise2Leg(
            ICashSettler.Exercise2LegData({
                optionType: ICashSettler.OptionType.CALL,
                optionsAmount: 50,
                optionId: itmcall,
                amount: 50,
                token: IERC20(address(memecoin)),
                amountSurplus: 0,
                poolToWeth: POOL_PEPE_WETH
            })
        );
    }

    function testRevert_exercise2Leg_whenInsufficientApprovalGranted() public {
        memecoin.approve(address(clearingHouse), type(uint256).max);

        clearingHouse.write(itmcall, 100);

        vm.expectRevert("NOT_AUTHORIZED");

        vault.exercise2Leg(
            ICashSettler.Exercise2LegData({
                optionType: ICashSettler.OptionType.CALL,
                optionId: itmcall,
                optionsAmount: 10,
                amount: 50,
                token: IERC20(address(memecoin)),
                amountSurplus: 0,
                poolToWeth: POOL_PEPE_WETH
            })
        );
    }

    ////####////####////####////####////####////####////
    ////####////####    Exercise        ####////####////
    ////####////####////####////####////####////####////

    // TODO revert exercise call when moneyness not enough to cover fees
    // TODO revert exercise put when moneyness not enough to cover fees
    // TODO revert exercise call when insufficient surplus
    // TODO revert exercise put when insufficient surplus
    // TODO revert when before exerciseTimestamp
    // TODO revert when after expiryTimestamp
    // TODO revert when can't flash loan sufficient exercise asset
    // TODO revert when haven't granted sufficient clearinghouse permission to vault
    // TODO revert when can't flash swap underlying asset to sufficient stablecoin

    function test_getQuote() public {
        uint256 input = 1e6;
        uint256 output = quoter.quoteExactInputSingle({
            tokenIn: address(USDC),
            tokenOut: address(WETH),
            fee: POOL_USDC_FEE,
            amountIn: input,
            sqrtPriceLimitX96: 0
        });

        emit log_named_uint("Quote", output);
    }

    function test_exercise_whenLINKCallOption() public withCallAtStrike(address(LINK), 6e6) {
        // background setup,  strike: 0.0000016000, spot: 0.0000017040
        LINK.approve(address(clearingHouse), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(admin);
        clearingHouse.setFeesEnabled(true);
        vm.stopPrank();

        // write 101 call options
        vm.startPrank(me);
        clearingHouse.write(callOption, 101);

        assertEq(clearingHouse.balanceOf(me, callOption), 101, "clearinghouse my balance background");
        assertEq(clearingHouse.balanceOf(you, callOption), 0, "clearinghouse your balance background");
        assertEq(clearingHouse.balanceOf(address(vault), callOption), 0, "clearinghouse vault balance background");
        assertEq(
            LINK.balanceOf(me),
            initialMEMEBalance - (1e18 * 101) - _valoremFee(1e18 * 101),
            "meme my balance background"
        );
        assertEq(USDC.balanceOf(me), initialUSDCBalance, "stable my balance background");
        assertEq(LINK.balanceOf(you), initialMEMEBalance, "meme your balance background");
        assertEq(USDC.balanceOf(you), initialUSDCBalance, "stable your balance background");
        assertEq(
            LINK.balanceOf(address(clearingHouse)),
            1e18 * 101 + _valoremFee(1e18 * 101),
            "meme clearinghouse balance background"
        );
        assertEq(USDC.balanceOf(address(clearingHouse)), 0, "stable clearinghouse balance background");

        // transfer 10 call option to you
        clearingHouse.safeTransferFrom(me, you, callOption, 10, "");

        assertEq(clearingHouse.balanceOf(me, callOption), 91, "clearinghouse my balance before exercise");
        assertEq(clearingHouse.balanceOf(you, callOption), 10, "clearinghouse your balance before exercise");
        assertEq(clearingHouse.balanceOf(address(vault), callOption), 0, "clearinghouse vault balance before exercise");
        assertEq(
            LINK.balanceOf(me),
            initialMEMEBalance - (1e18 * 101) - _valoremFee(1e18 * 101),
            "meme my balance before exercise"
        );
        assertEq(USDC.balanceOf(me), initialUSDCBalance, "stable my balance before exercise");
        assertEq(LINK.balanceOf(you), initialMEMEBalance, "meme your balance before exercise");
        assertEq(USDC.balanceOf(you), initialUSDCBalance, "stable your balance before exercise");
        assertEq(
            LINK.balanceOf(address(clearingHouse)),
            1e18 * 101 + _valoremFee(1e18 * 101),
            "meme clearinghouse balance before exercise"
        );
        assertEq(USDC.balanceOf(address(clearingHouse)), 0, "stable clearinghouse balance before exercise");

        // calculate amount needed for exercise
        uint112 memesAmount = 10;
        uint256 exerciseAmount = 6e6;
        uint256 assetRequiredInUSDC = memesAmount * exerciseAmount;

        // account for exercise fee
        assetRequiredInUSDC += _valoremFee(assetRequiredInUSDC);

        // account for USDC pool fee
        assetRequiredInUSDC += (assetRequiredInUSDC * POOL_USDC_FEE) / DIVISOR_HUNDREDTHS_OF_BPS;

        // account for MEME pool fee
        assetRequiredInUSDC += (assetRequiredInUSDC * POOL_LINK_FEE) / DIVISOR_HUNDREDTHS_OF_BPS;

        // convert to WETH
        uint256 assetRequiredInWETH = quoter.quoteExactInputSingle({
            tokenIn: address(USDC),
            tokenOut: address(WETH),
            fee: POOL_USDC_FEE,
            amountIn: assetRequiredInUSDC,
            sqrtPriceLimitX96: 0
        });

        // 0.000802/0.000000439103626452
        // emit log_named_uint("assetRequiredInUSDC", assetRequiredInUSDC);
        // emit log_named_uint("assetRequiredInWETH", assetRequiredInWETH);

        // calculate minimum surplus required
        // (this allows the exerciser to account for the premium they pay for the options)
        // in this example, you buy 10 calls at 0.1e6 USDC per call, for a total of 1e6 USDC
        uint256 minimumSurplusInUSDC = 0;

        // you exercise 10 memes
        vm.warp(expiry - 1 seconds);
        vm.stopPrank();
        vm.startPrank(you);

        clearingHouse.setApprovalForAll(address(vault), true);

        vm.expectEmit(true, true, true, true);
        emit Call(you, callOption, memesAmount);
        vault.exercise2Leg(
            ICashSettler.Exercise2LegData({
                optionType: ICashSettler.OptionType.CALL,
                optionId: callOption,
                optionsAmount: memesAmount,
                amount: assetRequiredInWETH,
                token: LINK,
                amountSurplus: minimumSurplusInUSDC,
                poolToWeth: POOL_LINK_WETH
            })
        );

        assertEq(clearingHouse.balanceOf(me, callOption), 91, "clearinghouse my balance after exercise");
        assertEq(clearingHouse.balanceOf(you, callOption), 0, "clearinghouse your balance after exercise");
        assertEq(clearingHouse.balanceOf(address(vault), callOption), 0, "clearinghouse vault balance after exercise");
        assertEq(
            LINK.balanceOf(me),
            initialMEMEBalance - (1e18 * 101) - _valoremFee(1e18 * 101),
            "meme my balance after exercise"
        );
        assertEq(USDC.balanceOf(me), initialUSDCBalance, "stable my balance after exercise");
        assertEq(LINK.balanceOf(you), initialMEMEBalance, "meme your balance after exercise");
        assertGt(USDC.balanceOf(you), initialUSDCBalance, "stable your balance after exercise");

        emit log_named_uint("Initial USDC balance of you", initialUSDCBalance);
        emit log_named_uint("After ex USDC balance of you", USDC.balanceOf(you));
        emit log_named_uint("Surplus USDC balance of you", USDC.balanceOf(you) - initialUSDCBalance);
        // emit log_named_uint("Profit USDC balance of you", USDC.balanceOf(you) - initialUSDCBalance - minimumSurplusInUSDC);

        assertEq(
            LINK.balanceOf(address(clearingHouse)),
            (1e18 * (101 - memesAmount)) + _valoremFee(1e18 * 101),
            "meme clearinghouse balance after exercise"
        );
        assertEq(
            USDC.balanceOf(address(clearingHouse)),
            (6e6 * memesAmount) + _valoremFee(6e6 * memesAmount),
            "stable clearinghouse balance after exercise"
        );

        vm.stopPrank();
    }

    function test_exercise_whenLINKPutOption() public withPutAtStrike(address(LINK), 7e6) {
        // as of block 17381236
        // ETH price in USD $1867.6456712677
        // LINK price in USD $6.4765624545
        // LINK price in WETH 0.0034677683 WETH
        // background setup
        USDC.approve(address(clearingHouse), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(admin);
        clearingHouse.setFeesEnabled(true);
        vm.stopPrank();

        // write 101 put options, create vault with 50 memes
        vm.startPrank(me);
        clearingHouse.write(putOption, 101);

        // TODO shhh, minting some extra tokens to Vault
        // deal(address(LINK), address(vault), 1_000_000_000e18);
        // deal(address(USDC), address(vault), 1_000_000_000e6);
        // deal(address(WETH), address(vault), 1_000_000_000_000e18);

        // check balances initial
        assertEq(clearingHouse.balanceOf(me, putOption), 101, "clearinghouse my balance background");
        assertEq(clearingHouse.balanceOf(you, putOption), 0, "clearinghouse your balance background");
        assertEq(clearingHouse.balanceOf(address(vault), putOption), 0, "clearinghouse vault balance background");
        assertEq(LINK.balanceOf(me), initialMEMEBalance, "meme my balance background");
        assertEq(
            USDC.balanceOf(me),
            initialUSDCBalance - (7e6 * 101) - _valoremFee(7e6 * 101),
            "stable my balance background"
        );
        assertEq(LINK.balanceOf(you), initialMEMEBalance, "meme your balance background");
        assertEq(USDC.balanceOf(you), initialUSDCBalance, "stable your balance background");
        assertEq(LINK.balanceOf(address(clearingHouse)), 0, "meme clearinghouse balance background");
        assertEq(
            USDC.balanceOf(address(clearingHouse)),
            (7e6 * 101) + _valoremFee(7e6 * 101),
            "stable clearinghouse balance background"
        );

        // transfer 10 put option to you
        clearingHouse.safeTransferFrom(me, you, putOption, 10, "");

        // check balances before exercise
        assertEq(clearingHouse.balanceOf(me, putOption), 91, "clearinghouse my balance before exercise");
        assertEq(clearingHouse.balanceOf(you, putOption), 10, "clearinghouse your balance before exercise");
        assertEq(clearingHouse.balanceOf(address(vault), putOption), 0, "clearinghouse vault balance before exercise");
        assertEq(LINK.balanceOf(me), initialMEMEBalance, "meme my balance before exercise");
        assertEq(
            USDC.balanceOf(me),
            initialUSDCBalance - (7e6 * 101) - _valoremFee(7e6 * 101),
            "stable my balance before exercise"
        );
        assertEq(LINK.balanceOf(you), initialMEMEBalance, "meme your balance before exercise");
        assertEq(USDC.balanceOf(you), initialUSDCBalance, "stable your balance before exercise");
        assertEq(LINK.balanceOf(address(clearingHouse)), 0, "meme clearinghouse balance before exercise");
        assertEq(
            USDC.balanceOf(address(clearingHouse)),
            (7e6 * 101) + _valoremFee(7e6 * 101),
            "stable clearinghouse balance before exercise"
        );

        // calculate amount needed for exercise
        uint112 memesAmount = 10;
        uint256 exerciseAmount = 1e18;
        uint256 assetRequiredInLINK = memesAmount * exerciseAmount;

        // account for exercise fee
        assetRequiredInLINK += _valoremFee(assetRequiredInLINK);
        console2.log("assetRequiredInLINK with valorem fee: ", assetRequiredInLINK);

        //     // account for MEME pool fee
        //     assetRequiredInLINK += (assetRequiredInLINK * POOL_LINK_FEE) / DIVISOR_HUNDREDTHS_OF_BPS;
        // console2.log("assetRequiredInLINK with valorem fee and meme pool fee: ", assetRequiredInLINK);
        //
        //     // account for USDC pool fee
        //     assetRequiredInLINK += (assetRequiredInLINK * POOL_USDC_FEE) / DIVISOR_HUNDREDTHS_OF_BPS;
        // console2.log("assetRequiredInLINK with valorem fee and meme pool fee and usdc pool fee: ", assetRequiredInLINK);

        // convert to WETH
        uint256 assetRequiredInWETH = quoter.quoteExactOutputSingle({
            tokenIn: address(WETH),
            tokenOut: address(LINK),
            fee: POOL_LINK_FEE,
            amountOut: assetRequiredInLINK,
            sqrtPriceLimitX96: 0
        });

        // 17328897297443165/5020016253750000000 = 0.00345196
        emit log_named_uint("assetRequiredInLINK", assetRequiredInLINK);
        emit log_named_uint("assetRequiredInWETH", assetRequiredInWETH);

        // calculate minimum surplus required
        // (this allows the exerciser to account for the premium they pay for the options)
        // in this example, you buy 10 puts at 0.1e6 USDC per put, for a total of 1e6 USDC
        // uint256 minimumSurplusInUSDC = assetRequiredInUSDC + 1e6;
        uint256 minimumSurplusInUSDC = 0;

        // you exercise 10 memes
        vm.warp(expiry - 1 seconds);
        vm.stopPrank();
        vm.startPrank(you);

        clearingHouse.setApprovalForAll(address(vault), true);

        vm.expectEmit(true, true, true, true);
        emit Put(you, putOption, memesAmount);
        vault.exercise2Leg(
            ICashSettler.Exercise2LegData({
                optionType: ICashSettler.OptionType.PUT,
                optionId: putOption,
                optionsAmount: memesAmount,
                amount: assetRequiredInWETH,
                token: LINK,
                amountSurplus: minimumSurplusInUSDC,
                poolToWeth: POOL_LINK_WETH
            })
        );
        // check balances after exercise
        assertEq(clearingHouse.balanceOf(me, putOption), 91, "clearinghouse my balance after exercise");
        assertEq(clearingHouse.balanceOf(you, putOption), 0, "clearinghouse your balance after exercise");
        assertEq(clearingHouse.balanceOf(address(vault), putOption), 0, "clearinghouse vault balance after exercise");
        assertEq(LINK.balanceOf(me), initialMEMEBalance, "meme my balance after exercise");
        assertEq(
            USDC.balanceOf(me),
            initialUSDCBalance - (7e6 * 101) - _valoremFee(7e6 * 101),
            "stable my balance after exercise"
        );
        assertEq(LINK.balanceOf(you), initialMEMEBalance, "meme your balance after exercise");
        assertGt(USDC.balanceOf(you), initialUSDCBalance, "stable your balance after exercise");
        assertEq(
            LINK.balanceOf(address(clearingHouse)),
            1e18 * 10 + _valoremFee(1e18 * 10),
            "meme clearinghouse balance after exercise"
        );
        assertEq(
            USDC.balanceOf(address(clearingHouse)),
            (7e6 * 101) + _valoremFee(7e6 * 101) - 7e6 * 10,
            "stable clearinghouse balance after exercise"
        );

        console2.log(StdStyle.blue("Balances ------"));
        // console2.log(StdStyle.blue("Initial USDC balance of you:"));
        // console2.log(StdStyle.blue(initialUSDCBalance));
        // console2.log(StdStyle.blue("After ex USDC balance of you:"));
        // console2.log(StdStyle.blue(USDC.balanceOf(you)));
        // console2.log(StdStyle.blue("Surplus USDC balance of you:"));
        // console2.log(StdStyle.blue(USDC.balanceOf(you) - initialUSDCBalance));
        emit log_named_uint("Initial USDC balance of you", initialUSDCBalance);
        emit log_named_uint("After ex USDC balance of you", USDC.balanceOf(you));
        emit log_named_uint("Surplus USDC balance of you", USDC.balanceOf(you) - initialUSDCBalance);
        // emit log_named_uint("Profit USDC balance of you", USDC.balanceOf(you) - initialUSDCBalance - minimumSurplusInUSDC);

        vm.stopPrank();
    }

    // TODO
    // function testRevert_exercise_whenDontHoldSufficientMemes()
    //     public
    //     vaultForOptionTypeWithXLongsAndYMemes(otmcall, 100, 50)
    // {
    //     vm.expectRevert(abi.encodeWithSelector(Memevault.LowMemes.selector, me, 51, 50));

    //     vault.exercise(51, 123, 0);

    //     vm.stopPrank();
    //     vm.startPrank(you);
    //     vm.expectRevert(abi.encodeWithSelector(Memevault.LowMemes.selector, me, 1, 0));
    //     vault.exercise(1, 123, 0);

    //     vm.stopPrank();
    // }

    // function test_exercise_whenCallOption() public withCallAtStrike(address(PEPE), 160) {
    //     // background setup,  strike: 0.0000016000, spot: 0.0000017040
    //     PEPE.approve(address(clearingHouse), type(uint256).max);
    //     clearingHouse.setApprovalForAll(address(factory), true);
    //     vm.stopPrank();
    //     vm.startPrank(admin);
    //     clearingHouse.setFeesEnabled(true);
    //     vm.stopPrank();

    //     // write 101 call options, create vault with 50 memes
    //     vm.startPrank(me);
    //     clearingHouse.write(callOption, 101);
    //     vault = Memevault(factory.create(callOption, address(PEPE), POOL_PEPE_WETH, 50));

    //     // TODO shhh, minting some extra USDC to Vault to cover flash fee
    //     deal(address(USDC), address(vault), 1_000_000_000e6);

    //     assertEq(vault.totalSupply(), 50, "vault total supply background");
    //     assertEq(vault.balanceOf(me), 50, "vault my balance background");
    //     assertEq(vault.balanceOf(you), 0, "vault your balance background");
    //     assertEq(clearingHouse.balanceOf(me, callOption), 51, "clearinghouse my balance background");
    //     assertEq(clearingHouse.balanceOf(you, callOption), 0, "clearinghouse your balance background");
    //     assertEq(clearingHouse.balanceOf(address(vault), callOption), 50, "clearinghouse vault balance background");
    //     assertEq(
    //         PEPE.balanceOf(me),
    //         initialMEMEBalance - (100e18 * 101) - _valoremFee(100e18 * 101),
    //         "meme my balance background"
    //     );
    //     assertEq(USDC.balanceOf(me), initialUSDCBalance, "stable my balance background");
    //     assertEq(PEPE.balanceOf(you), initialMEMEBalance, "meme your balance background");
    //     assertEq(USDC.balanceOf(you), initialUSDCBalance, "stable your balance background");
    //     assertEq(
    //         PEPE.balanceOf(address(clearingHouse)),
    //         100e18 * 101 + _valoremFee(100e18 * 101),
    //         "meme clearinghouse balance background"
    //     );
    //     assertEq(USDC.balanceOf(address(clearingHouse)), 0, "stable clearinghouse balance background");

    //     // transfer 5 memes and 1 call option to you
    //     vault.transfer(you, 5);
    //     clearingHouse.safeTransferFrom(me, you, callOption, 1, "");

    //     assertEq(vault.totalSupply(), 50, "vault total supply before exercise");
    //     assertEq(vault.balanceOf(me), 45, "vault my balance before exercise");
    //     assertEq(vault.balanceOf(you), 5, "vault your balance before exercise");
    //     assertEq(clearingHouse.balanceOf(me, callOption), 50, "clearinghouse my balance before exercise");
    //     assertEq(clearingHouse.balanceOf(you, callOption), 1, "clearinghouse your balance before exercise");
    //     assertEq(clearingHouse.balanceOf(address(vault), callOption), 50, "clearinghouse vault balance before exercise");
    //     assertEq(
    //         PEPE.balanceOf(me),
    //         initialMEMEBalance - (100e18 * 101) - _valoremFee(100e18 * 101),
    //         "meme my balance before exercise"
    //     );
    //     assertEq(USDC.balanceOf(me), initialUSDCBalance, "stable my balance before exercise");
    //     assertEq(PEPE.balanceOf(you), initialMEMEBalance, "meme your balance before exercise");
    //     assertEq(USDC.balanceOf(you), initialUSDCBalance, "stable your balance before exercise");
    //     assertEq(
    //         PEPE.balanceOf(address(clearingHouse)),
    //         100e18 * 101 + _valoremFee(100e18 * 101),
    //         "meme clearinghouse balance before exercise"
    //     );
    //     assertEq(USDC.balanceOf(address(clearingHouse)), 0, "stable clearinghouse balance before exercise");

    //     // you exercise 5 memes
    //     vm.warp(expiry - 1 seconds);
    //     vm.stopPrank();
    //     vm.startPrank(you);
    //     USDC.approve(address(clearingHouse), type(uint256).max);
    //     clearingHouse.setApprovalForAll(address(vault), true);
    //     vault.exercise(5, 0);

    //     assertEq(vault.totalSupply(), 45, "vault total supply after exercise");
    //     assertEq(vault.balanceOf(me), 45, "vault my balance after exercise");
    //     assertEq(vault.balanceOf(you), 0, "vault your balance after exercise");
    //     assertEq(clearingHouse.balanceOf(me, callOption), 50, "clearinghouse my balance after exercise");
    //     assertEq(clearingHouse.balanceOf(you, callOption), 1, "clearinghouse your balance after exercise");
    //     assertEq(clearingHouse.balanceOf(address(vault), callOption), 45, "clearinghouse vault balance after exercise");
    //     assertEq(
    //         PEPE.balanceOf(me),
    //         initialMEMEBalance - (100e18 * 101) - _valoremFee(100e18 * 101),
    //         "meme my balance after exercise"
    //     );
    //     assertEq(USDC.balanceOf(me), initialUSDCBalance, "stable my balance after exercise");
    //     assertEq(PEPE.balanceOf(you), initialMEMEBalance, "meme your balance after exercise");
    //     assertEq(
    //         USDC.balanceOf(you),
    //         initialUSDCBalance - (160 * 5) - _valoremFee(160 * 5) - _uniswapLoanFees(666)
    //             + _uniswapSwapFees(100e18 * 5),
    //         "stable your balance after exercise"
    //     );
    //     assertEq(
    //         PEPE.balanceOf(address(clearingHouse)),
    //         (100e18 * (101 - 5)) + _valoremFee(100e18 * 101),
    //         "meme clearinghouse balance after exercise"
    //     );
    //     assertEq(
    //         USDC.balanceOf(address(clearingHouse)),
    //         (160 * 5) + _valoremFee(160 * 5),
    //         "stable clearinghouse balance after exercise"
    //     );

    //     vm.stopPrank();
    // }
}

////####////####////####////####////####////####////####////####////####////####////####////####////####////####
////####////####////####////####////####////####////####////####////####////####////####////####////####////####
////####////####////####////####////####////####////####////####////####////####////####////####////####////####

contract Memecoin is ERC20 {
    constructor() ERC20("Memecoin International", "MEME", 6) {}

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}

contract Stablecoin is ERC20 {
    constructor() ERC20("Unstable Symps Do X", "USDX", 9) {}

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}
