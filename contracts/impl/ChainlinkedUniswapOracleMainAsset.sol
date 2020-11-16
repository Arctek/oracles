// SPDX-License-Identifier: bsl-1.1

/*
  Copyright 2020 Unit Protocol: Artem Zakharov (az@unit.xyz).
*/
pragma solidity ^0.6.8;
pragma experimental ABIEncoderV2;

import "../helpers/SafeMath.sol";
import { UniswapOracle, IUniswapV2Pair } from  '@keydonix/uniswap-oracle-contracts/source/UniswapOracle.sol';
import "../helpers/AggregatorInterface.sol";
import "../helpers/IUniswapV2Factory.sol";
import "../abstract/ChainlinkedUniswapOracleMainAssetAbstract.sol";


/**
 * @title ChainlinkedUniswapOracleMainAsset
 * @author Unit Protocol: Artem Zakharov (az@unit.xyz), Alexander Ponomorev (@bcngod)
 * @dev Calculates the USD price of desired tokens
 **/
contract ChainlinkedUniswapOracleMainAsset is UniswapOracle, ChainlinkedUniswapOracleMainAssetAbstract {
    using SafeMath for uint;

    uint8 public constant MIN_BLOCKS_BACK = uint8(100);

    uint8 public constant MAX_BLOCKS_BACK = uint8(255);

    uint public constant ETH_USD_DENOMINATOR = 100000000;

    AggregatorInterface public ethUsdChainlinkAggregator;

    IUniswapV2Factory public uniswapFactory;

    constructor(
        IUniswapV2Factory uniFactory,
        address weth,
        AggregatorInterface chainlinkAggregator
    )
        public
    {
        require(address(uniFactory) != address(0), "Unit Protocol: ZERO_ADDRESS");
        require(weth != address(0), "Unit Protocol: ZERO_ADDRESS");
        require(address(chainlinkAggregator) != address(0), "Unit Protocol: ZERO_ADDRESS");

        uniswapFactory = uniFactory;
        WETH = weth;
        ethUsdChainlinkAggregator = chainlinkAggregator;
    }

    /**
     * @notice USD token's rate is UniswapV2 Token/WETH pool's average price between proof's blockNumber and current block number
     * @notice Merkle proof must be in range [MIN_BLOCKS_BACK ... MAX_BLOCKS_BACK] blocks ago
     * @notice {Token}/WETH pair must be registered on Uniswap
     * @param asset The token address
     * @param amount Amount of tokens
     * @return Q112-encoded price of tokens in USD
     **/
    function assetToUsd(address asset, uint amount, ProofData memory proofData) public override view returns (uint) {

        uint priceInEth = assetToEth(
            asset,
            amount,
            proofData
        );
        return ethToUsd(priceInEth);
    }

    /**
     * @notice USD token's rate is UniswapV2 Token/WETH pool's average price between proof's blockNumber and current block number
     * @notice Merkle proof must be in range [MIN_BLOCKS_BACK ... MAX_BLOCKS_BACK] blocks ago
     * @notice {Token}/WETH pair must be registered on Uniswap
     * @param asset The token address
     * @param amount Amount of tokens
     * @return Q112-encoded price of asset in ETH
     **/
    function assetToEth(address asset, uint amount, ProofData memory proofData) public override view returns (uint) {
        if (amount == 0) {
            return 0;
        }

        if (asset == WETH) {
            return amount.mul(Q112);
        }

        IUniswapV2Pair pair = IUniswapV2Pair(uniswapFactory.getPair(asset, WETH));
        require(address(pair) != address(0), "Unit Protocol: UNISWAP_PAIR_DOES_NOT_EXIST");

        (uint priceInEth, ) = getPrice(
            pair,
            WETH,
            MIN_BLOCKS_BACK,
            MAX_BLOCKS_BACK,
            proofData
        );
        return priceInEth.mul(amount);
    }

    /**
     * @notice ETH/USD price feed from Chainlink, see for more info: https://feeds.chain.link/eth-usd
     * returns Price of given amount of Ether in USD (0 decimals)
     **/
    function ethToUsd(uint ethAmount) public override view returns (uint) {
        require(ethUsdChainlinkAggregator.latestTimestamp() > now - 6 hours, "Unit Protocol: STALE_CHAINLINK_PRICE");
        uint ethUsdPrice = uint(ethUsdChainlinkAggregator.latestAnswer());
        return ethAmount.mul(ethUsdPrice).div(ETH_USD_DENOMINATOR);
    }
}
