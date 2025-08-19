// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Fuego Ξmbers Token (HEAT)
 * @dev Fuego Ξmbers (HEAT) token minted on Arbitrum by burning XFG on Fuego
 * @dev Only the HEATBurnProofVerifier can mint new tokens
 * @dev Standardized burn amount: 0.8 XFG = 8M HEAT
 * @dev Also serves as gas token for CODL3 rollup
 */
contract EmbersTokenHEAT is ERC20, Ownable, Pausable, ReentrancyGuard {
    
    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */
    
    event HEATMinted(address indexed to, uint256 amount, uint256 timestamp);
    event HEATBurned(address indexed from, uint256 amount, uint256 timestamp);
    event HEATCollectedForGas(address indexed from, uint256 amount, uint256 timestamp);
    event HEATBurnedForGas(address indexed from, uint256 amount, uint256 timestamp);
    event HEATBurnedByTreasury(address indexed treasury, uint256 amount, uint256 timestamp);
    event MinterUpdated(address indexed oldMinter, address indexed newMinter);
    event CODL3GasCollectorUpdated(address indexed oldCollector, address indexed newCollector);
    event CODL3TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    
    /* -------------------------------------------------------------------------- */
    /*                                   State                                    */
    /* -------------------------------------------------------------------------- */
    
    /// @dev Only this contract can mint HEAT tokens
    address public minter;
    
    /// @dev Only CODL3 rollup can collect HEAT for gas fees
    address public codl3GasCollector;
    
    /// @dev CODL3 treasury address for gas fee collection
    address public codl3Treasury;
    
    /// @dev Total HEAT minted through XFG burns
    uint256 public totalMintedFromBurns;
    
    /// @dev Total HEAT burned (user burns)
    uint256 public totalBurned;
    
    /// @dev Total HEAT collected for CODL3 gas fees (2% to treasury)
    uint256 public totalCollectedForGas;
    
    /// @dev Total HEAT burned for CODL3 gas fees (8% immediate burn)
    uint256 public totalBurnedForGas;
    
    /// @dev Total HEAT burned by treasury (quarterly)
    uint256 public totalBurnedByTreasury;
    
    /// @dev Backstop maximum supply of HEAT tokens (42 trillion)
    /// @dev This is a theoretical backstop, not actively enforced
    uint256 public constant BACKSTOP_MAX_SUPPLY = 42_000_000_000_000 * 10**18;
    
    /// @dev Standardized XFG burn amount (0.8 XFG)
    uint256 public constant STANDARDIZED_XFG_BURN = 800_000; // 0.8 XFG in smallest units
    
    /// @dev Standardized HEAT mint amount (8M HEAT)
    uint256 public constant STANDARDIZED_HEAT_MINT = 8_000_000 * 10**18;
    
    /// @dev Large XFG burn amount (8000 XFG)
    uint256 public constant LARGE_XFG_BURN = 80_000_000_000; // 8000 XFG in smallest units
    
    /// @dev Large HEAT mint amount (80B HEAT)
    uint256 public constant LARGE_HEAT_MINT = 80_000_000_000 * 10**18;
    
    /* -------------------------------------------------------------------------- */
    /*                                 Constructor                                */
    /* -------------------------------------------------------------------------- */
    
    constructor(
        address _initialOwner,
        address _initialMinter
    ) ERC20(unicode"Fuego Ξmbers", "HEAT") Ownable(_initialOwner) {
        require(_initialMinter != address(0), "Invalid minter address");
        minter = _initialMinter;
        codl3GasCollector = address(0); // Will be set when CODL3 is deployed
        codl3Treasury = address(0); // Will be set when CODL3 treasury is deployed
        
        // No premint supply - all HEAT comes from XFG burns
    }
    
    /* -------------------------------------------------------------------------- */
    /*                              Minting Functions                             */
    /* -------------------------------------------------------------------------- */
    
    /**
     * @dev Mint HEAT tokens from XFG burn proof verification
     * @param to Recipient of the HEAT tokens
     * @param amount Amount of HEAT to mint (8M HEAT for 0.8 XFG burn or 80B HEAT for 8000 XFG burn)
     */
    function mintFromBurnProof(address to, uint256 amount) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        require(msg.sender == minter, "Only minter can mint from burn proofs");
        require(to != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be greater than 0");
        require(
            amount == STANDARDIZED_HEAT_MINT || amount == LARGE_HEAT_MINT,
            "Amount must be 8M HEAT (0.8 XFG) or 80B HEAT (8000 XFG)"
        );
        require(totalSupply() + amount <= BACKSTOP_MAX_SUPPLY, "Would exceed backstop max supply");
        
        _mint(to, amount);
        totalMintedFromBurns += amount;
        
        emit HEATMinted(to, amount, block.timestamp);
    }
    
    /**
     * @dev Emergency mint function for owner (only for emergency situations)
     * @param to Recipient of the HEAT tokens
     * @param amount Amount of HEAT to mint
     */
    function emergencyMint(address to, uint256 amount) 
        external 
        onlyOwner 
        whenNotPaused 
    {
        require(to != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be greater than 0");
        require(totalSupply() + amount <= BACKSTOP_MAX_SUPPLY, "Would exceed backstop max supply");
        
        _mint(to, amount);
        
        emit HEATMinted(to, amount, block.timestamp);
    }
    
    /* -------------------------------------------------------------------------- */
    /*                              Burning Functions                             */
    /* -------------------------------------------------------------------------- */
    
    /**
     * @dev Burn HEAT tokens
     * @param amount Amount of HEAT to burn
     */
    function burn(uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        _burn(msg.sender, amount);
        totalBurned += amount;
        
        emit HEATBurned(msg.sender, amount, block.timestamp);
    }
    
    /**
     * @dev Burn HEAT tokens from a specific address (with allowance)
     * @param from Address to burn from
     * @param amount Amount of HEAT to burn
     */
    function burnFrom(address from, uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(from) >= amount, "Insufficient balance");
        require(allowance(from, msg.sender) >= amount, "Insufficient allowance");
        
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
        totalBurned += amount;
        
        emit HEATBurned(from, amount, block.timestamp);
    }
    
    /* -------------------------------------------------------------------------- */
    /*                           CODL3 Gas Functions                              */
    /* -------------------------------------------------------------------------- */
    
    /**
     * @dev Collect HEAT tokens for CODL3 gas fees (only callable by CODL3 rollup)
     * @param from Address to collect HEAT from
     * @param totalAmount Total amount of HEAT for gas fees
     * @dev 8% burned immediately, 2% sent to treasury, 90% to miners/validators
     */
    function collectForCODL3Gas(address from, uint256 totalAmount) 
        external 
        whenNotPaused 
    {
        require(msg.sender == codl3GasCollector, "Only CODL3 gas collector can collect for gas");
        require(from != address(0), "Cannot collect from zero address");
        require(totalAmount > 0, "Amount must be greater than 0");
        require(balanceOf(from) >= totalAmount, "Insufficient balance");
        
        // Calculate fee distribution
        uint256 burnAmount = (totalAmount * 8) / 100; // 8% burned immediately
        uint256 treasuryAmount = (totalAmount * 2) / 100; // 2% to treasury
        uint256 minerAmount = totalAmount - burnAmount - treasuryAmount; // 90% to miners
        
        // Burn 8% immediately
        _burn(from, burnAmount);
        totalBurnedForGas += burnAmount;
        emit HEATBurnedForGas(from, burnAmount, block.timestamp);
        
        // Transfer 2% to treasury
        _transfer(from, codl3Treasury, treasuryAmount);
        totalCollectedForGas += treasuryAmount;
        emit HEATCollectedForGas(from, treasuryAmount, block.timestamp);
        
        // Transfer 90% to miners/validators (handled by CODL3)
        // Note: This amount is already deducted from user's balance above
        // CODL3 will handle the distribution to miners/validators
    }
    
    /**
     * @dev Collect HEAT tokens for CODL3 gas fees with allowance (only callable by CODL3 rollup)
     * @param from Address to collect HEAT from
     * @param spender Address that has allowance
     * @param totalAmount Total amount of HEAT for gas fees
     * @dev 8% burned immediately, 2% sent to treasury, 90% to miners/validators
     */
    function collectForCODL3GasFrom(address from, address spender, uint256 totalAmount) 
        external 
        whenNotPaused 
    {
        require(msg.sender == codl3GasCollector, "Only CODL3 gas collector can collect for gas");
        require(from != address(0), "Cannot collect from zero address");
        require(totalAmount > 0, "Amount must be greater than 0");
        require(balanceOf(from) >= totalAmount, "Insufficient balance");
        require(allowance(from, spender) >= totalAmount, "Insufficient allowance");
        
        // Calculate fee distribution
        uint256 burnAmount = (totalAmount * 8) / 100; // 8% burned immediately
        uint256 treasuryAmount = (totalAmount * 2) / 100; // 2% to treasury
        uint256 minerAmount = totalAmount - burnAmount - treasuryAmount; // 90% to miners
        
        // Spend allowance for the total amount
        _spendAllowance(from, spender, totalAmount);
        
        // Burn 8% immediately
        _burn(from, burnAmount);
        totalBurnedForGas += burnAmount;
        emit HEATBurnedForGas(from, burnAmount, block.timestamp);
        
        // Transfer 2% to treasury
        _transfer(from, codl3Treasury, treasuryAmount);
        totalCollectedForGas += treasuryAmount;
        emit HEATCollectedForGas(from, treasuryAmount, block.timestamp);
        
        // Transfer 90% to miners/validators (handled by CODL3)
        // Note: This amount is already deducted from user's balance above
        // CODL3 will handle the distribution to miners/validators
    }
    
    /**
     * @dev Burn HEAT tokens from treasury (only callable by treasury)
     * @param amount Amount of HEAT to burn
     */
    function burnFromTreasury(uint256 amount) 
        external 
        whenNotPaused 
    {
        require(msg.sender == codl3Treasury, "Only CODL3 treasury can burn from treasury");
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(codl3Treasury) >= amount, "Insufficient treasury balance");
        
        _burn(codl3Treasury, amount);
        totalBurnedByTreasury += amount;
        
        emit HEATBurnedByTreasury(codl3Treasury, amount, block.timestamp);
    }
    
    /* -------------------------------------------------------------------------- */
    /*                              Admin Functions                               */
    /* -------------------------------------------------------------------------- */
    
    /**
     * @dev Update the minter address
     * @param newMinter New minter address
     */
    function updateMinter(address newMinter) external onlyOwner {
        require(newMinter != address(0), "Invalid minter address");
        address oldMinter = minter;
        minter = newMinter;
        
        emit MinterUpdated(oldMinter, newMinter);
    }
    
    /**
     * @dev Update the CODL3 gas collector address
     * @param newGasCollector New CODL3 gas collector address
     */
    function updateCODL3GasCollector(address newGasCollector) external onlyOwner {
        address oldGasCollector = codl3GasCollector;
        codl3GasCollector = newGasCollector;
        
        emit CODL3GasCollectorUpdated(oldGasCollector, newGasCollector);
    }
    
    /**
     * @dev Update the CODL3 treasury address
     * @param newTreasury New CODL3 treasury address
     */
    function updateCODL3Treasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Invalid treasury address");
        address oldTreasury = codl3Treasury;
        codl3Treasury = newTreasury;
        
        emit CODL3TreasuryUpdated(oldTreasury, newTreasury);
    }
    
    /**
     * @dev Pause all token transfers and minting
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause all token transfers and minting
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /* -------------------------------------------------------------------------- */
    /*                              View Functions                                */
    /* -------------------------------------------------------------------------- */
    
    /**
     * @dev Get token statistics
     * @return _totalSupply Current total supply
     * @return _totalMintedFromBurns Total minted from XFG burns
     * @return _totalBurned Total burned (user burns)
     * @return _totalCollectedForGas Total collected for CODL3 gas fees (2% to treasury)
     * @return _totalBurnedForGas Total burned for CODL3 gas fees (8% immediate burn)
     * @return _totalBurnedByTreasury Total burned by treasury (quarterly)
     * @return _backstopMaxSupply Backstop maximum supply
     */
    function getStats() external view returns (
        uint256 _totalSupply,
        uint256 _totalMintedFromBurns,
        uint256 _totalBurned,
        uint256 _totalCollectedForGas,
        uint256 _totalBurnedForGas,
        uint256 _totalBurnedByTreasury,
        uint256 _backstopMaxSupply
    ) {
        return (
            totalSupply(),
            totalMintedFromBurns,
            totalBurned,
            totalCollectedForGas,
            totalBurnedForGas,
            totalBurnedByTreasury,
            BACKSTOP_MAX_SUPPLY
        );
    }
    
    /**
     * @dev Check if an address is the current minter
     * @param addr Address to check
     * @return True if address is the minter
     */
    function isMinter(address addr) external view returns (bool) {
        return addr == minter;
    }
    
    /**
     * @dev Check if an address is the current CODL3 gas collector
     * @param addr Address to check
     * @return True if address is the CODL3 gas collector
     */
    function isCODL3GasCollector(address addr) external view returns (bool) {
        return addr == codl3GasCollector;
    }
    
    /**
     * @dev Check if an address is the current CODL3 treasury
     * @param addr Address to check
     * @return True if address is the CODL3 treasury
     */
    function isCODL3Treasury(address addr) external view returns (bool) {
        return addr == codl3Treasury;
    }
    
    /* -------------------------------------------------------------------------- */
    /*                              Override Functions                            */
    /* -------------------------------------------------------------------------- */
    
    /**
     * @dev Override transfer to check for paused state
     */
    function transfer(address to, uint256 amount) 
        public 
        override 
        whenNotPaused 
        returns (bool) 
    {
        return super.transfer(to, amount);
    }
    
    /**
     * @dev Override transferFrom to check for paused state
     */
    function transferFrom(address from, address to, uint256 amount) 
        public 
        override 
        whenNotPaused 
        returns (bool) 
    {
        return super.transferFrom(from, to, amount);
    }
    
    /**
     * @dev Override approve to check for paused state
     */
    function approve(address spender, uint256 amount) 
        public 
        override 
        whenNotPaused 
        returns (bool) 
    {
        return super.approve(spender, amount);
    }
    

}
