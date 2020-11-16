// SPDX-License-Identifier: bsl-1.1

/*
  Copyright 2020 Unit Protocol: Artem Zakharov (az@unit.xyz).
*/
pragma solidity ^0.6.8;
pragma experimental ABIEncoderV2;

import "../helpers/SafeMath.sol";
import "../helpers/AggregatorInterface.sol";
import "../helpers/Keep3rV1OracleAbstract.sol";
import "../helpers/IUniswapV2Factory.sol";
import "../helpers/UniswapV2Library.sol";
import "../helpers/UniswapV2OracleLibrary.sol";
import "../abstract/OracleSimple.sol";


/**
 * @title ChainlinkedKeep3rV1OracleMainAsset
 * @author Unit Protocol: Artem Zakharov (az@unit.xyz), Alexander Ponomorev (@bcngod)
 * @dev Calculates the USD price of desired tokens
 **/
contract ChainlinkedKeep3rV1OracleMainAsset is ChainlinkedOracleSimple {
    using SafeMath for uint;

    uint public immutable periodSize = 1800;

    uint public immutable Q112 = 2 ** 112;

    uint public immutable ETH_USD_DENOMINATOR = 100000000;

    AggregatorInterface public immutable ethUsdChainlinkAggregator;

    Keep3rV1OracleAbstract public immutable keep3rV1Oracle;

    IUniswapV2Factory public immutable uniswapFactory;

    constructor(
        IUniswapV2Factory _uniFactory,
        Keep3rV1OracleAbstract _keep3rV1Oracle,
        address weth,
        AggregatorInterface chainlinkAggregator
    )
        public
    {
        require(address(_uniFactory) != address(0), "Unit Protocol: ZERO_ADDRESS");
        require(address(_keep3rV1Oracle) != address(0), "Unit Protocol: ZERO_ADDRESS");
        require(weth != address(0), "Unit Protocol: ZERO_ADDRESS");
        require(address(chainlinkAggregator) != address(0), "Unit Protocol: ZERO_ADDRESS");

        uniswapFactory = _uniFactory;
        keep3rV1Oracle = _keep3rV1Oracle;
        WETH = weth;
        ethUsdChainlinkAggregator = chainlinkAggregator;
    }

    /**
     * @notice {Token}/WETH pair must be registered on Uniquote
     * @param asset The token address
     * @param amount Amount of tokens
     * @return Q112-encoded price of asset amount in USD
     **/
    function assetToUsd(address asset, uint amount) public override view returns (uint) {
        return ethToUsd(assetToEth(asset, amount));
    }

    /**
     * @notice {asset}/WETH pair must be registered at Keep3rV1Oracle
     * @param asset The token address
     * @param amount Amount of tokens
     * @return Q112-encoded price of asset amount in ETH
     **/
    function assetToEth(address asset, uint amount) public view override returns (uint) {
        if (asset == WETH) {
            return amount.mul(Q112);
        }
        return keep3rCurrent(asset, amount);
    }

    /**
     * @notice {asset}/WETH price feed from uniquote.finance, see for more info: https://docs.uniquote.finance/
     * @param tokenIn The token in address
     * @param amountIn Amount of tokens in
     * returns Q112-encoded current asset price in ETH
     **/
    function keep3rCurrent(address tokenIn, uint amountIn) public view returns (uint amountOut) {
        address pair = UniswapV2Library.pairFor(address(uniswapFactory), tokenIn, WETH);
        (address token0,) = UniswapV2Library.sortTokens(tokenIn, WETH);
        uint observationLength = keep3rV1Oracle.observationLength(pair);
        require(observationLength > 1, "Unit Protocol: NOT_ENOUGH_OBSERVTIONS");

        uint obseravationIndex = observationLength - 1;
        uint timestampObs; uint price0CumulativeObs; uint price1CumulativeObs;
        (timestampObs, price0CumulativeObs, price1CumulativeObs) = keep3rV1Oracle.observations(pair, obseravationIndex);
        (uint price0Cumulative, uint price1Cumulative,) = UniswapV2OracleLibrary.currentCumulativePrices(pair);
        while (block.timestamp - timestampObs < periodSize) {
            obseravationIndex -= 1;
            (timestampObs, price0CumulativeObs, price1CumulativeObs) = keep3rV1Oracle.observations(pair, obseravationIndex);
        }
        uint timeElapsed = block.timestamp - timestampObs;
        require(timeElapsed <= periodSize.mul(2), "Unit Protocol: STALE_PRICES");

        if (token0 == tokenIn) {
            return computeAmountOut(price0CumulativeObs, price0Cumulative, timeElapsed, amountIn);
        } else {
            return computeAmountOut(price1CumulativeObs, price1Cumulative, timeElapsed, amountIn);
        }
    }

    // returns Q112-encoded value
    function computeAmountOut(
        uint priceCumulativeStart, uint priceCumulativeEnd,
        uint timeElapsed, uint amountIn
    ) private pure returns (uint) {
        // overflow is desired
        uint avgPrice = (priceCumulativeEnd - priceCumulativeStart) / timeElapsed;
        return avgPrice.mul(amountIn);
    }

    /**
     * @notice ETH/USD price feed from Chainlink, see for more info: https://feeds.chain.link/eth-usd
     * returns The price of given amount of Ether in USD (0 decimals)
     **/
    function ethToUsd(uint ethAmount) public override view returns (uint) {
        require(ethUsdChainlinkAggregator.latestTimestamp() > now - 6 hours, "Unit Protocol: STALE_CHAINLINK_PRICE");
        uint ethUsdPrice = uint(ethUsdChainlinkAggregator.latestAnswer());
        return ethAmount.mul(ethUsdPrice).div(ETH_USD_DENOMINATOR);
    }
}
