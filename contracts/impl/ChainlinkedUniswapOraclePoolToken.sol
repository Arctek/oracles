// SPDX-License-Identifier: bsl-1.1

/*
  Copyright 2020 Unit Protocol: Artem Zakharov (az@unit.xyz).
*/
pragma solidity ^0.6.8;
pragma experimental ABIEncoderV2;

import "../helpers/SafeMath.sol";
import "../helpers/IUniswapV2PairFull.sol";
import "../abstract/ChainlinkedUniswapOracleMainAssetAbstract.sol";
import "../abstract/ChainlinkedUniswapOraclePoolTokenAbstract.sol";


/**
 * @title ChainlinkedUniswapOraclePoolToken
 * @author Unit Protocol: Artem Zakharov (az@unit.xyz), Alexander Ponomorev (@bcngod)
 * @dev Calculates the USD price of Uniswap LP tokens
 **/
contract ChainlinkedUniswapOraclePoolToken is ChainlinkedUniswapOraclePoolTokenAbstract {
    using SafeMath for uint;

    uint public constant magicNum1 = 9;
    uint public constant magicNum2 = 3988000;
    uint public constant magicNum3 = 1997;
    uint public constant magicNum4 = 2000;
    uint public constant magicNum5 = 3;
    uint public constant magicNum6 = 2;

    constructor(address _uniswapOracleMainAsset) public {
        uniswapOracleMainAsset = ChainlinkedUniswapOracleMainAssetAbstract(_uniswapOracleMainAsset);
    }

    /**
     * @notice This function implements flashloan-resistant logic to determine USD price of Uniswap LP tokens
     * @notice Block number of merkle proof must be in range [MIN_BLOCKS_BACK ... MAX_BLOCKS_BACK] blocks ago (see ChainlinkedUniswapOracle)
     * @notice Pair must be registered on Uniswap
     * @param asset The LP token address
     * @param amount Amount of asset
     * @param proofData The proof data of underlying token price
     * @return Q112 encoded price of asset in USD
     **/
    function assetToUsd(
        address asset,
        uint amount,
        UniswapOracle.ProofData memory proofData
    )
        public
        override
        view
        returns (uint)
    {
        IUniswapV2PairFull pair = IUniswapV2PairFull(asset);
        address underlyingAsset;
        if (pair.token0() == uniswapOracleMainAsset.WETH()) {
            underlyingAsset = pair.token1();
        } else if (pair.token1() == uniswapOracleMainAsset.WETH()) {
            underlyingAsset = pair.token0();
        } else {
            revert("USDP: NOT_REGISTERED_PAIR");
        }

        uint eAvg = uniswapOracleMainAsset.assetToEth(underlyingAsset, 1, proofData); // average price of 1 token in ETH

        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves();
        uint aPool; // current asset pool
        uint ePool; // current WETH pool
        if (pair.token0() == underlyingAsset) {
            aPool = uint(_reserve0);
            ePool = uint(_reserve1);
        } else {
            aPool = uint(_reserve1);
            ePool = uint(_reserve0);
        }

        uint eCurr = ePool.mul(Q112).div(aPool); // current price of 1 token in WETH
        uint ePoolCalc; // calculated WETH pool

        if (eCurr < eAvg) {
            // flashloan with buying WETH
            uint sqrtd = ePool.mul((ePool).mul(magicNum1).add(
                aPool.mul(magicNum2).mul(eAvg).div(Q112)
            ));
            uint eChange = sqrt(sqrtd).sub(ePool.mul(magicNum3)).div(magicNum4);
            ePoolCalc = ePool.add(eChange);
        } else {
            // flashloan with selling WETH
            uint a = aPool.mul(eAvg);
            uint b = a.mul(magicNum1).div(Q112);
            uint c = ePool.mul(magicNum2);
            uint sqRoot = sqrt(a.div(Q112).mul(b.add(c)));
            uint d = a.mul(magicNum5).div(Q112);
            uint eChange = ePool.sub(d.add(sqRoot).div(magicNum4));
            ePoolCalc = ePool.sub(eChange);
        }

        uint num = ePoolCalc.mul(magicNum6).mul(amount).mul(Q112);
        uint priceInEth = num.div(pair.totalSupply());

        return uniswapOracleMainAsset.ethToUsd(priceInEth);
    }

    function sqrt(uint x) internal pure returns (uint y) {
        if (x > 3) {
            uint z = x / 2 + 1;
            y = x;
            while (z < y) {
                y = z;
                z = (x / z + z) / 2;
            }
        } else if (x != 0) {
            y = 1;
        }
    }
}
