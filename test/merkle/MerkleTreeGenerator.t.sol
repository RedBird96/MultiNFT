// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./MerkleTreeGenerator.sol";
import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

contract MerkleTreeGeneratorTest is Test {
    MerkleTreeGenerator m;

    function setUp() public {
        m = new MerkleTreeGenerator();
    }

    function testGenerateProof(bytes32[] memory data, uint256 node) public view {
        vm.assume(data.length > 1);
        vm.assume(node < data.length);
        bytes32 root = m.getRoot(data);
        bytes32[] memory proof = m.getProof(data, node);
        bytes32 valueToProve = data[node];

        bytes32 rollingHash = valueToProve;
        for (uint256 i = 0; i < proof.length; ++i) {
            rollingHash = m.hashLeafPairs(rollingHash, proof[i]);
        }
        assertEq(rollingHash, root);
    }

    function testVerifyProofSucceedsForGoodValue(bytes32[] memory data, uint256 node) public view {
        vm.assume(data.length > 1);
        vm.assume(node < data.length);
        bytes32 root = m.getRoot(data);
        bytes32[] memory proof = m.getProof(data, node);
        bytes32 valueToProve = data[node];
        assertTrue(m.verifyProof(root, proof, valueToProve));
    }

    function testVerifyProofFailsForBadValue(bytes32[] memory data, bytes32 valueToProve, uint256 node) public view {
        vm.assume(data.length > 1);
        vm.assume(node < data.length);
        vm.assume(valueNotInArray(data, valueToProve));
        bytes32 root = m.getRoot(data);
        bytes32[] memory proof = m.getProof(data, node);
        assertFalse(m.verifyProof(root, proof, valueToProve));
    }

    function testVerifyProofOzForGasComparison(bytes32[] memory data, uint256 node) public view {
        vm.assume(data.length > 1);
        vm.assume(node < data.length);
        bytes32 root = m.getRoot(data);
        bytes32[] memory proof = m.getProof(data, node);
        bytes32 valueToProve = data[node];
        assertTrue(MerkleProof.verify(proof, root, valueToProve));
    }

    function testWontGetRootSingleLeaf() public {
        bytes32[] memory data = new bytes32[](1);
        data[0] = bytes32(0x0);
        vm.expectRevert("wont generate root for single leaf");
        m.getRoot(data);
    }

    function testWontGetProofSingleLeaf() public {
        bytes32[] memory data = new bytes32[](1);
        data[0] = bytes32(0x0);
        vm.expectRevert("wont generate proof for single leaf");
        m.getProof(data, 0x0);
    }

    function valueNotInArray(bytes32[] memory data, bytes32 value) public pure returns (bool) {
        for (uint256 i = 0; i < data.length; ++i) {
            if (data[i] == value) return false;
        }
        return true;
    }

    function testVerifyWithAddressesArray() public view {
        address[] memory whitelistAddresses = new address[](3);
        whitelistAddresses[0] = address(0x5B38Da6a701c568545dCfcB03FcB875f56beddC4);
        whitelistAddresses[1] = address(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2);
        whitelistAddresses[2] = address(0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db);

        bytes32[] memory hashAddresses = new bytes32[](3);
        hashAddresses[0] = keccak256(abi.encodePacked(whitelistAddresses[0]));
        hashAddresses[1] = keccak256(abi.encodePacked(whitelistAddresses[1]));
        hashAddresses[2] = keccak256(abi.encodePacked(whitelistAddresses[2]));

        bytes32 root = m.getRoot(hashAddresses);
        bytes32[] memory proof = m.getProof(hashAddresses, 0);
        assertTrue(MerkleProof.verify(proof, root, hashAddresses[0]));
    }
}
