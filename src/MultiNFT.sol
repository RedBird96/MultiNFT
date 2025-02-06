// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "forge-std/Test.sol";

contract MultiNFT is ERC721Enumerable, ReentrancyGuard {
    using ECDSA for bytes32; // Use ECDSA for signature recovery
    using MessageHashUtils for bytes32; // Use MessageHashUtils for Ethereum signed message hashing

    // Enum to represent the different minting phases
    enum Phase {
        Phase1,
        Phase2,
        Phase3
    }

    Phase public currentPhase; // Current minting phase
    IERC20 public token; // ERC20 token used for payment
    bytes32 public phase1MerkleRoot; // Merkle root for Phase 1 whitelist
    bytes32 public phase2MerkleRoot; // Merkle root for Phase 2 whitelist
    address public owner;
    uint256 public phase2Price; // Price for Phase 2 minting
    uint256 public phase3Price; // Price for Phase 3 minting

    mapping(address => bool) public mintPool; // Tracks addresses that have minted
    mapping(bytes => bool) public usedSignature; // Tracks used signatures to prevent reuse

    // Vesting variables
    uint256 public totalVestedAmount; // Total amount of tokens locked in vesting
    uint256 public vestingStartTime; // Timestamp when vesting starts
    uint256 public constant VESTING_DURATION = 365 days; // Vesting duration (1 year)

    event Minted(address indexed user, uint256 tokenId, uint256 price); // Emitted when an NFT is minted
    event TokensClaimed(address indexed owner, uint256 amount); // Emitted when vested tokens are claimed

    /**
     * CONSTRUCTOR
     *
     *
     */
     /// @param _phase1MerkleRoot The merkle root for phase1 whitelist users
     /// @param _phase2MerkleRoot The merkle root for phase2 whitelist users
     /// @param _token The token address for payment
     /// @param _price1 The price for phase2 minting users, it's discounted price
     /// @param _price2 The price for phase3 minting users, it's full price
    constructor(bytes32 _phase1MerkleRoot, bytes32 _phase2MerkleRoot, address _token, uint256 _price1, uint256 _price2)
        ERC721("MultiNFT", "MyNFT")
    {
        phase1MerkleRoot = _phase1MerkleRoot;
        phase2MerkleRoot = _phase2MerkleRoot;
        token = IERC20(_token);
        phase2Price = _price1;
        phase3Price = _price2;
        owner = msg.sender;
    }

    /**
     *
     * MODIFIER
     *
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Not Owner");
        _;
    }

    /// @notice Set the current phase of minting
    /// @param _phase The phase for setting
    function setPhase(Phase _phase) external onlyOwner {
        currentPhase = _phase;
    }

    /// @notice Set the owner of this contract
    /// @param _owner Owner address
    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    /// @notice Mint function for phase1 whitelisted users
    /// @dev At phase1, the whitelisted users can mint without fee
    /// @param pr The proof of current user to check the leaves of merkle tree
    function mintFree(bytes32[] calldata pr) external nonReentrant {
        require(currentPhase == Phase.Phase1, "Not Phase1");
        require(!mintPool[msg.sender], "Already Minted");
        require(_verifyMerkleProof(pr, phase1MerkleRoot), "Invalid Proof");
        _mintAndEmit(0);
    }

    /// @notice Mint function for phase2 whitelisted users
    /// @dev At phase2, the whitelisted users can mint with discounted fee
    /// @param pr The proof of current user to check the leaves of merkle tree
    /// @param signature The signature of this user
    function mintWithDiscount(bytes32[] calldata pr, bytes calldata signature) external nonReentrant {
        require(currentPhase == Phase.Phase2, "Not Phase2");
        require(!usedSignature[signature], "Already Used Signature");
        require(!mintPool[msg.sender], "Already Minted");
        require(_verifyMerkleProof(pr, phase2MerkleRoot), "Invalid Proof");

        // Verify the signature that the signer is owner
        bytes32 msgHash = keccak256(abi.encodePacked(msg.sender, phase2Price));
        bytes32 signedHash = MessageHashUtils.toEthSignedMessageHash(msgHash);
        address signer = ECDSA.recover(signedHash, signature);
        require(signer == owner, "Invalid signature");

        // Mint NFT and transfer the fee to this contract
        _mintAndEmit(phase2Price);
        token.transferFrom(msg.sender, address(this), phase2Price);
        _updateVestingInfo(phase2Price);

        // Update signature map to prevent reuse the signature
        usedSignature[signature] = true;
    }

    /// @notice Mint function for normal users
    /// @dev At phase3, normal user can mint NFT with full price fee
    function mintNFT() external nonReentrant {
        require(currentPhase == Phase.Phase3, "Not Phase3");
        require(!mintPool[msg.sender], "Already Minted");

        _mintAndEmit(phase3Price);
        token.transferFrom(msg.sender, address(this), phase3Price);
        _updateVestingInfo(phase3Price);
    }

    /// @notice Claim vested tokens only callable by the owner
    /// @dev Only owner can claim vested tokens with linear vesting logic
    function claimVestedTokens() external onlyOwner nonReentrant {
        require(vestingStartTime > 0, "Vesting not started");

        // Calculate the elapsed time since vesting started
        uint256 elapsedTime = block.timestamp - vestingStartTime;
        uint256 vestedAmount;

        // Calculate the vested amount based on elapsed time
        if (elapsedTime >= VESTING_DURATION) {
            vestedAmount = totalVestedAmount;
        } else {
            vestedAmount = (totalVestedAmount * elapsedTime) / VESTING_DURATION;
        }

        require(vestedAmount > 0, "No tokens vested");

        // Transfer vested tokens to the owner
        token.transfer(owner, vestedAmount);
        totalVestedAmount -= vestedAmount;

        emit TokensClaimed(owner, vestedAmount);
    }

    /// @notice Get the total vested amount
    /// @return totalVestedAmount total vested amount
    function getTotalVestedAmount() external view returns (uint256) {
        return totalVestedAmount;
    }

    /// @notice Verify merkle proof with the leaf
    /// @param proof merkle proof of this user
    /// @param root merkle root
    function _verifyMerkleProof(bytes32[] calldata proof, bytes32 root) internal view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        return MerkleProof.verify(proof, root, leaf);
    }

    /// @notice Mint NFT and emit
    /// @param _price the price for emit log
    function _mintAndEmit(uint256 _price) internal {
        mintPool[msg.sender] = true;
        uint256 id = totalSupply() + 1;

        _mint(msg.sender, id);
        emit Minted(msg.sender, id, _price);
    }

    /// @notice Update the total vested amount after mint token
    /// @param _amount The amount of vesting
    function _updateVestingInfo(uint256 _amount) internal {
        totalVestedAmount += _amount;
        if (vestingStartTime == 0) {
            vestingStartTime = block.timestamp;
        }
    }
}
