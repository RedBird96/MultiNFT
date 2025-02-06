// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/MultiNFT.sol";
import "../src/Token.sol";
import "./merkle/MerkleTreeGenerator.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract MultiNFTTest is Test {
    MultiNFT public nft;
    MerkleTreeGenerator merkleTreeGenerator;
    PToken public tk;
    uint256 private privateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address public owner;
    address public user1 = address(0x456);
    address public user2 = address(0x654);
    address public user3 = address(0x546);
    address public user4 = address(0x4567);
    address public user5 = address(0x7654);
    address public user6 = address(0x45678);
    bytes32 public phase1MerkleRoot;
    bytes32 public phase2MerkleRoot;
    bytes32[] whitelistAddressesHashPhase1;
    bytes32[] whitelistAddressesHashPhase2;
    uint256 public fullPrice = 1_000;
    uint256 public discountPrice = 500;

    function setUp() public {
        // Deploy the MerkleTreeGenerator
        merkleTreeGenerator = new MerkleTreeGenerator();

        whitelistAddressesHashPhase1.push(keccak256(abi.encodePacked(user1)));
        whitelistAddressesHashPhase1.push(keccak256(abi.encodePacked(user2)));
        whitelistAddressesHashPhase1.push(keccak256(abi.encodePacked(user3)));

        whitelistAddressesHashPhase2.push(keccak256(abi.encodePacked(user4)));
        whitelistAddressesHashPhase2.push(keccak256(abi.encodePacked(user5)));

        // Get merkle root for phase1 and phase2
        phase1MerkleRoot = merkleTreeGenerator.getRoot(whitelistAddressesHashPhase1);
        phase2MerkleRoot = merkleTreeGenerator.getRoot(whitelistAddressesHashPhase2);

        // Derive the owner address from the private key
        owner = vm.addr(privateKey);

        vm.startPrank(owner);

        // Transfer payment token to each users
        tk = new PToken();
        tk.transfer(user4, discountPrice);
        tk.transfer(user5, discountPrice);
        tk.transfer(user6, fullPrice);

        // Deploy NFT contract with phase1, phase2 merkle root
        nft = new MultiNFT(phase1MerkleRoot, phase2MerkleRoot, address(tk), discountPrice, fullPrice);
        vm.stopPrank();
    }

    function testOnlyOwnerCanSetPhase() public {
        vm.expectRevert("Not Owner");
        nft.setPhase(MultiNFT.Phase.Phase1);

        vm.prank(user1);
        vm.expectRevert("Not Owner");
        nft.setPhase(MultiNFT.Phase.Phase1);

        vm.prank(owner);
        nft.setPhase(MultiNFT.Phase.Phase2);
        MultiNFT.Phase cuPhase = nft.currentPhase();
        assertTrue(cuPhase == MultiNFT.Phase.Phase2);
    }

    function testMintFreeOnlyPhase1() public {
        vm.prank(owner);
        nft.setPhase(MultiNFT.Phase.Phase2);

        // Get proof of the user1
        bytes32[] memory proof = merkleTreeGenerator.getProof(whitelistAddressesHashPhase1, 0);
        vm.expectRevert("Not Phase1");
        nft.mintFree(proof);
    }

    function testOnlyWhitelistedUserCanParticipatePhase1() public {
        // Get proof of the user4
        bytes32[] memory proof = merkleTreeGenerator.getProof(whitelistAddressesHashPhase2, 0);

        vm.prank(owner);
        nft.setPhase(MultiNFT.Phase.Phase1);

        // Try mint with user4 which is not whitelisted for phase1
        vm.prank(user4);
        vm.expectRevert("Invalid Proof");
        nft.mintFree(proof);
    }

    function testMintFreeOneTime() public {
        // Get proof of the user1
        bytes32[] memory proof = merkleTreeGenerator.getProof(whitelistAddressesHashPhase1, 0);

        vm.startPrank(user1);
        nft.mintFree(proof);

        assertEq(nft.balanceOf(user1), 1);

        vm.expectRevert("Already Minted");
        nft.mintFree(proof);
        vm.stopPrank();
    }

    function testMintFree() public {
        // Get proof of the user1
        bytes32[] memory proof = merkleTreeGenerator.getProof(whitelistAddressesHashPhase1, 0);

        vm.prank(user1);
        nft.mintFree(proof);

        assertEq(nft.balanceOf(user1), 1);
    }

    function testOnlyWhitelistedUserCanParticipatePhase2() public {
        vm.prank(owner);
        nft.setPhase(MultiNFT.Phase.Phase2);

        // Get proof of the user1
        bytes32[] memory proof = merkleTreeGenerator.getProof(whitelistAddressesHashPhase1, 0);

        // Generate the signature of user1
        bytes memory signature = getSignature(user1, discountPrice, privateKey);

        // Try mint with user1 which is not whitelisted for phase2
        vm.prank(user1);
        vm.expectRevert("Invalid Proof");
        nft.mintWithDiscount(proof, signature);
    }

    function testOnlyUniqueSignatureCanBeUsed() public {
        vm.prank(owner);
        nft.setPhase(MultiNFT.Phase.Phase2);

        // Get proof of the user1
        bytes32[] memory proof = merkleTreeGenerator.getProof(whitelistAddressesHashPhase2, 0);
        // Generate the signature of user1
        bytes memory signature = getSignature(user4, discountPrice, privateKey);

        // Try mint with user1 which is not whitelisted for phase2
        vm.startPrank(user4);
        tk.approve(address(nft), discountPrice);
        nft.mintWithDiscount(proof, signature);

        vm.expectRevert("Already Used Signature");
        nft.mintWithDiscount(proof, signature);
        vm.stopPrank();
    }

    function testOnlyOwnerSignatureCanBeUsed() public {
        vm.prank(owner);
        nft.setPhase(MultiNFT.Phase.Phase2);

        uint256 fakePrivateKey = 0x1234;
        // Get proof of the user1
        bytes32[] memory proof = merkleTreeGenerator.getProof(whitelistAddressesHashPhase2, 0);
        // Generate the signature of user1
        bytes memory signature = getSignature(user4, discountPrice, fakePrivateKey);

        // Try mint with user1 which is not whitelisted for phase2
        vm.prank(user4);
        vm.expectRevert("Invalid signature");
        nft.mintWithDiscount(proof, signature);
    }

    function testMintWithDiscount() public {
        // Generate the signature
        bytes memory signature = getSignature(user4, discountPrice, privateKey);

        // Get proof of the user4
        bytes32[] memory proof = merkleTreeGenerator.getProof(whitelistAddressesHashPhase2, 0);

        uint256 beforeVestedAmount = nft.getTotalVestedAmount();
        // Set Phase2
        vm.prank(owner);
        nft.setPhase(MultiNFT.Phase.Phase2);
        // Mint with discount
        vm.startPrank(user4);
        tk.approve(address(nft), discountPrice);
        nft.mintWithDiscount(proof, signature);
        vm.stopPrank();

        // Verify that the user received an NFT
        assertEq(nft.balanceOf(user4), 1);
        uint256 afterVestedAmount = nft.getTotalVestedAmount();
        assertTrue(afterVestedAmount - beforeVestedAmount == discountPrice);
    }

    function testMintNFT() public {
        // Set Phase3
        vm.prank(owner);
        nft.setPhase(MultiNFT.Phase.Phase3);

        uint256 beforeVestedAmount = nft.getTotalVestedAmount();
        vm.startPrank(user6);
        tk.approve(address(nft), fullPrice);
        nft.mintNFT();
        vm.stopPrank();

        // Verify that the user received an NFT
        assertEq(nft.balanceOf(user6), 1);

        uint256 afterVestedAmount = nft.getTotalVestedAmount();
        assertTrue(afterVestedAmount - beforeVestedAmount == fullPrice);
    }

    function testOnlyOwnerCanClaim() public {
        vm.prank(user1);
        vm.expectRevert("Not Owner");
        nft.claimVestedTokens();
    }

    function testCantClaimBeforeStart() public {
        vm.prank(owner);
        vm.expectRevert("Vesting not started");
        nft.claimVestedTokens();
    }

    function testClaimVestingToken() public {
        // Set Phase3
        vm.prank(owner);
        nft.setPhase(MultiNFT.Phase.Phase3);

        // Mint NFT of normal user6
        vm.startPrank(user6);
        tk.approve(address(nft), fullPrice);
        nft.mintNFT();
        vm.stopPrank();

        // Check the vested amount after the mint token
        // Check the total vested amount has increased
        uint256 vestedAmount = nft.getTotalVestedAmount();
        assertTrue(vestedAmount > 0);

        uint256 currentTimestamp = block.timestamp;
        uint256 newTimestamp = currentTimestamp + 100 days;
        vm.warp(newTimestamp);

        // After 100days, check the owner can claim vested token as totalVestedAmount * 100/365
        uint256 beforeBalance = tk.balanceOf(owner);
        vm.prank(owner);
        nft.claimVestedTokens();
        uint256 afterBalance = tk.balanceOf(owner);
        uint256 amount = afterBalance - beforeBalance;
        assertEq(amount, fullPrice * 100 / 365);

        // After 365 days, check all totalVestedAmount can be claimed
        newTimestamp = currentTimestamp + 365 days;
        vm.warp(newTimestamp);
        vm.prank(owner);
        nft.claimVestedTokens();
        afterBalance = tk.balanceOf(owner);
        amount = afterBalance - beforeBalance;
        assertEq(amount, fullPrice);
    }

    function getSignature(address user, uint256 price, uint256 prKey) internal pure returns (bytes memory) {
        // Generate the signature
        bytes32 messageHash = keccak256(abi.encodePacked(user, price));
        bytes32 signedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(prKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        return signature;
    }
}
