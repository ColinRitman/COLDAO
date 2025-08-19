// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./HEATToken.sol";

/**
 * @title Fuego Ξmbers Burn Proof Verifier
 * @dev Verifies XFG burn proofs and mints HEAT tokens on Arbitrum
 * @dev Only this contract can mint HEAT tokens through burn proof verification
 * @dev Standardized burn amount: 0.8 XFG = 8M HEAT
 * @dev Privacy-focused: No address restrictions, recommend new addresses per claim
 */
contract HEATBurnProofVerifier is Ownable, Pausable, ReentrancyGuard {
    
    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */
    
    event ProofVerified(
        bytes32 indexed burnTxHash,
        address indexed recipient,
        uint256 amount,
        bytes32 indexed nullifier
    );
    
    event PrivacyViolation(
        address indexed violator,
        string reason
    );
    
    /* -------------------------------------------------------------------------- */
    /*                                   State                                    */
    /* -------------------------------------------------------------------------- */
    
    /// @dev HEAT token contract
    EmbersTokenHEAT public immutable heatToken;
    
    /// @dev STARK proof verifier contract
    address public immutable verifier;
    
    /// @dev Standardized XFG burn amount (0.8 XFG)
    uint256 public constant STANDARDIZED_XFG_BURN = 800_000; // 0.8 XFG in smallest units
    
    /// @dev Standardized HEAT mint amount (8,000,000 HEAT)
    uint256 public constant STANDARDIZED_HEAT_MINT = 8_000_000 * 10**18;
    
    /// @dev Large XFG burn amount (8000 XFG)
    uint256 public constant LARGE_XFG_BURN = 80_000_000_000; // 8000 XFG in smallest units
    
    /// @dev Large HEAT mint amount (80,000,000,000 HEAT)
    uint256 public constant LARGE_HEAT_MINT = 80_000_000_000 * 10**18;
    
    /// @dev Fuego network ID (chain ID) - 46414e44-4f4d-474f-4c44-001210110110
    uint256 public constant FUEGO_NETWORK_ID = 93385046440755750514194170694064996624;
    
    /// @dev Used nullifiers to prevent double-spending
    mapping(bytes32 => bool) public nullifiersUsed;
    
    /// @dev Statistics
    uint256 public totalProofsVerified;
    uint256 public totalHEATMinted;
    uint256 public totalClaims;
    
    /* -------------------------------------------------------------------------- */
    /*                                 Constructor                                */
    /* -------------------------------------------------------------------------- */
    
    constructor(
        address _heatToken,
        address _verifier,
        address initialOwner
    ) Ownable(initialOwner) {
        require(_heatToken != address(0), "Invalid HEAT token address");
        require(_verifier != address(0), "Invalid verifier address");
        
        heatToken = EmbersTokenHEAT(_heatToken);
        verifier = _verifier;
    }
    
    /* -------------------------------------------------------------------------- */
    /*                              Core Functions                                */
    /* -------------------------------------------------------------------------- */
    
    /**
     * @dev Claim HEAT tokens by providing XFG burn proof with network validation
     * @param secret Secret from XFG transaction extra field
     * @param proof STARK proof bytes
     * @param publicInputs Public inputs for proof verification [nullifier, commitment, recipientHash, networkId]
     * @param recipient Address to receive HEAT tokens
     * @param isLargeBurn True for 8000 XFG burn (80B HEAT), false for 0.8 XFG burn (8M HEAT)
     */
    function claimHEAT(
        bytes32 secret,
        bytes calldata proof,
        bytes32[] calldata publicInputs,
        address recipient,
        bool isLargeBurn
    ) external whenNotPaused nonReentrant {
        require(recipient != address(0), "Invalid recipient address");
        require(publicInputs.length == 4, "Invalid public inputs length (need 4: nullifier, commitment, recipientHash, networkId)");
        
        // Extract public inputs
        bytes32 nullifier = publicInputs[0];
        bytes32 commitment = publicInputs[1];
        bytes32 recipientHash = publicInputs[2];
        uint256 networkId = uint256(publicInputs[3]);
        
        // Verify nullifier hasn't been used
        require(!nullifiersUsed[nullifier], "Nullifier already used");
        
        // Verify recipient hash matches
        require(
            recipientHash == keccak256(abi.encodePacked(recipient)),
            "Recipient hash mismatch"
        );
        
        // Verify network ID
        require(
            networkId == FUEGO_NETWORK_ID,
            "Invalid network ID"
        );
        
        // Verify STARK proof using the verifier contract
        bool proofValid = _verifyProof(proof, publicInputs);
        require(proofValid, "Invalid STARK proof");
        
        // Mark nullifier as used
        nullifiersUsed[nullifier] = true;
        
        // Determine mint amount based on burn type
        uint256 mintAmount = isLargeBurn ? LARGE_HEAT_MINT : STANDARDIZED_HEAT_MINT;
        
        // Mint HEAT tokens
        heatToken.mintFromBurnProof(recipient, mintAmount);
        
        // Update statistics
        totalProofsVerified += 1;
        totalHEATMinted += mintAmount;
        totalClaims += 1;
        
        emit ProofVerified(
            keccak256(abi.encodePacked(secret, commitment)),
            recipient,
            mintAmount,
            nullifier
        );
    }
    
    /**
     * @dev Verify STARK proof using the verifier contract
     * @param proof STARK proof bytes
     * @param publicInputs Public inputs for verification
     * @return True if proof is valid
     */
    function _verifyProof(
        bytes calldata proof,
        bytes32[] calldata publicInputs
    ) internal view returns (bool) {
        // Call the Winterfell verifier contract
        (bool success, bytes memory result) = verifier.staticcall(
            abi.encodeWithSignature(
                "verifyProof(bytes,bytes32[])",
                proof,
                publicInputs
            )
        );
        
        if (!success) {
            return false;
        }
        
        // Parse the result
        bool isValid = abi.decode(result, (bool));
        return isValid;
    }
    

    
    /* -------------------------------------------------------------------------- */
    /*                              View Functions                                */
    /* -------------------------------------------------------------------------- */
    
    /**
     * @dev Check if a nullifier has been used
     * @param nullifier Nullifier to check
     * @return True if nullifier has been used
     */
    function isNullifierUsed(bytes32 nullifier) external view returns (bool) {
        return nullifiersUsed[nullifier];
    }
    

    
    /**
     * @dev Get contract statistics
     * @return _totalProofsVerified Total proofs verified
     * @return _totalHEATMinted Total HEAT minted
     * @return _totalClaims Total claims made
     */
    function getStats() external view returns (
        uint256 _totalProofsVerified,
        uint256 _totalHEATMinted,
        uint256 _totalClaims
    ) {
        return (
            totalProofsVerified,
            totalHEATMinted,
            totalClaims
        );
    }
    
    /**
     * @dev Get conversion rates
     * @return _heatPerXfg HEAT per XFG
     * @return _standardizedBurn Standardized burn amount
     * @return _standardizedMint Standardized mint amount
     */
    function getConversionRates() external pure returns (
        uint256 _heatPerXfg,
        uint256 _standardizedBurn,
        uint256 _standardizedMint
    ) {
        return (
            10_000_000 * 10**18, // HEAT per XFG (1 XFG = 10M HEAT)
            STANDARDIZED_XFG_BURN,
            STANDARDIZED_HEAT_MINT
        );
    }
    
    /**
     * @dev Get burn and mint amounts for both burn types
     * @return standardizedXfgBurn Standardized XFG burn amount (0.8 XFG)
     * @return standardizedHeatMint Standardized HEAT mint amount (8M HEAT)
     * @return largeXfgBurn Large XFG burn amount (8000 XFG)
     * @return largeHeatMint Large HEAT mint amount (80B HEAT)
     */
    function getBurnMintAmounts() external pure returns (
        uint256 standardizedXfgBurn,
        uint256 standardizedHeatMint,
        uint256 largeXfgBurn,
        uint256 largeHeatMint
    ) {
        return (STANDARDIZED_XFG_BURN, STANDARDIZED_HEAT_MINT, LARGE_XFG_BURN, LARGE_HEAT_MINT);
    }
    
    /* -------------------------------------------------------------------------- */
    /*                              Admin Functions                               */
    /* -------------------------------------------------------------------------- */
    
    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Emergency function to recover stuck tokens
     * @param token Token address to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function emergencyRecover(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        
        if (token == address(0)) {
            // Recover ETH
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // Recover ERC20 tokens
            require(
                IERC20(token).transfer(to, amount),
                "Token transfer failed"
            );
        }
    }
    
    /**
     * @dev Emergency function to update HEAT token minter (if needed)
     * @param newMinter New minter address
     */
    function emergencyUpdateMinter(address newMinter) external onlyOwner {
        require(newMinter != address(0), "Invalid minter address");
        heatToken.updateMinter(newMinter);
    }
    
    /* -------------------------------------------------------------------------- */
    /*                              Receive Function                              */
    /* -------------------------------------------------------------------------- */
    
    /**
     * @dev Allow contract to receive ETH (for emergency recovery)
     */
    receive() external payable {}
}


