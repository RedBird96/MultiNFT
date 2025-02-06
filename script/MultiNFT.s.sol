// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./BaseDeployer.s.sol";
import "../src/MultiNFT.sol";
import "../src/Token.sol";

contract MultiNFTScript is BaseDeployer {

    MultiNFT public nft;
    PToken public pt;
    bytes32 public phase1MerkleRoot;
    bytes32 public phase2MerkleRoot;
    uint256 public fullPrice;
    uint256 public discountPrice;

    function setUp() public {
        fullPrice = 1_000;
        discountPrice = 500;
    }

    function run() public {
        vm.broadcast();
    }

    function nftDeployTestnet() external setEnvDeploy(Cycle.Test) {
        createSelectFork(Chains.Sepolia);
        _chainMultiNFT();
    }

    function nftDeploySelectedChains() external setEnvDeploy(Cycle.Prod){
        createSelectFork(Chains.Arbitrum);
        _chainMultiNFT();
    }

    function _chainMultiNFT() private broadcast(_deployerPrivateKey) {
        pt = new PToken();
        nft = new MultiNFT(
            phase1MerkleRoot,
            phase2MerkleRoot,
            address(pt),
            discountPrice,
            fullPrice
        );
    }
}