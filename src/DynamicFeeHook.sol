// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";


contract DynamicFeeHook is BaseHook {
    using LPFeeLibrary for uint24;

    uint24 public constant BASE_FEE = 5000; // 0.5%
    uint128 public movingAverageGasPrice;
    uint104 public movingAverageGasPriceCount;

    error MustBeDynamicFee();

    constructor(IPoolManager _manager) BaseHook(_manager) {
        _updateMovingAverageGasPrice();
    }

    function getHookPermissions()
            public
            pure
            override
            returns (Hooks.Permissions memory)
        {
            return
                Hooks.Permissions({
                    beforeInitialize: true,
                    afterInitialize: false,
                    beforeAddLiquidity: false,
                    beforeRemoveLiquidity: false,
                    afterAddLiquidity: false,
                    afterRemoveLiquidity: false,
                    beforeSwap: true,
                    afterSwap: true,
                    beforeDonate: false,
                    afterDonate: false,
                    beforeSwapReturnDelta: false,
                    afterSwapReturnDelta: false,
                    afterAddLiquidityReturnDelta: false,
                    afterRemoveLiquidityReturnDelta: false
                });
        }

    function beforeInitialize(address, PoolKey calldata key, uint160) 
    external pure override returns (bytes4) 
    {
        if(!key.fee.isDynamicFee()) {
            revert MustBeDynamicFee();
        }
        return(this.beforeInitialize.selector);
    }

    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
    external
    override
    onlyPoolManager
    returns (bytes4, BeforeSwapDelta, uint24) {
        uint24 fee = _getFee();
        uint24 feeWithFlag = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        return(this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, feeWithFlag);
    }

    function afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, int128) {
		_updateMovingAverageGasPrice();
        return (this.afterSwap.selector, 0);
    }

    // Internal functions 
    function _updateMovingAverageGasPrice() internal {
        uint128 currentGasPrice = uint128(tx.gasprice); 

        movingAverageGasPrice = (movingAverageGasPrice * movingAverageGasPriceCount + currentGasPrice) / (movingAverageGasPriceCount + 1);
        movingAverageGasPriceCount++;

    }

    function _getFee() internal view returns(uint24) {
        if(tx.gasprice >= (movingAverageGasPrice * 11) / 10) {
            return BASE_FEE / 2; 
        }
        if(tx.gasprice <= (movingAverageGasPrice * 9) / 10) {
            return BASE_FEE * 2;
        }
        
        return BASE_FEE;
    }

}