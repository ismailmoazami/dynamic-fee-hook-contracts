// SPDX-License-Identifier: MIT
pragma solidity 0.8.26; 

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {console} from "forge-std/console.sol";
import {DynamicFeeHook} from "../src/DynamicFeeHook.sol";

contract DynamicFeeHookTest is Test, Deployers {

    using CurrencyLibrary for Currency;
    using LPFeeLibrary for uint24; 
    using PoolIdLibrary for PoolKey;

    uint24 public constant INITIAL_FEE = 5000; // 0.5%

    DynamicFeeHook hook;

    function setUp() public {

        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        
        address hookAddress = address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG));
        vm.txGasPrice(10 gwei);
        deployCodeTo(
             "DynamicFeeHook.sol",
             abi.encode(manager),
             hookAddress
        );
        hook = DynamicFeeHook(hookAddress);

        (key, ) = initPool(currency0, currency1, hook, LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60, 
                liquidityDelta: 100 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

    }

    function test_can_reduce_or_increase_fee() external {

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false, settleUsingBurn: false
        });
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true, 
            amountSpecified: -0.0001 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        // Current gas price is 10 gwei and moving average should be 10
        uint256 gasPrice = uint256(tx.gasprice);
        uint256 movingAverage = hook.movingAverageGasPrice();
        uint256 movingAverageCount = hook.movingAverageGasPriceCount();
        assertEq(gasPrice, 10 gwei);
        assertEq(movingAverage, 10 gwei);
        assertEq(movingAverageCount, 1);

        // normal swap with base fee(0.5%)       
        uint256 balanceOfCurrency1BeforeSwap = currency1.balanceOfSelf();
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        uint256 balanceOfCurrency1AfterSwap = currency1.balanceOfSelf(); 
        uint256 outputAfterNormalSwap = balanceOfCurrency1AfterSwap - balanceOfCurrency1BeforeSwap;
        assertGt(balanceOfCurrency1AfterSwap, balanceOfCurrency1BeforeSwap); 

        movingAverage = hook.movingAverageGasPrice();
        movingAverageCount = hook.movingAverageGasPriceCount();
        assertEq(movingAverage, 10 gwei);
        assertEq(movingAverageCount, 2);

        // swap with 13 gwei gas fee
        vm.txGasPrice(13 gwei);
        balanceOfCurrency1BeforeSwap = currency1.balanceOfSelf(); 
        swapRouter.swap(key, params, testSettings, ZERO_BYTES); 
        balanceOfCurrency1AfterSwap = currency1.balanceOfSelf();  
        uint256 outputAfterHigherGasFeeSwap = balanceOfCurrency1AfterSwap - balanceOfCurrency1BeforeSwap;
        assertGt(balanceOfCurrency1AfterSwap, balanceOfCurrency1BeforeSwap); 

        movingAverage = hook.movingAverageGasPrice();
        movingAverageCount = hook.movingAverageGasPriceCount();
        assertEq(movingAverage, 11 gwei);
        assertEq(movingAverageCount, 3);

        // swap with 8 gwei gas fee 
        vm.txGasPrice(8 gwei);
        balanceOfCurrency1BeforeSwap = currency1.balanceOfSelf(); 
        swapRouter.swap(key, params, testSettings, ZERO_BYTES); 
        balanceOfCurrency1AfterSwap = currency1.balanceOfSelf();  
        uint256 outputAfterLowerGasFeeSwap = balanceOfCurrency1AfterSwap - balanceOfCurrency1BeforeSwap;
        assertGt(balanceOfCurrency1AfterSwap, balanceOfCurrency1BeforeSwap);
        
        movingAverage = hook.movingAverageGasPrice();
        movingAverageCount = hook.movingAverageGasPriceCount();
        assertEq(movingAverage, 10.25 gwei);
        assertEq(movingAverageCount, 4);

        // final tests 
        assertGt(outputAfterNormalSwap, outputAfterLowerGasFeeSwap);
        assertGt(outputAfterHigherGasFeeSwap, outputAfterNormalSwap); 

    }

}