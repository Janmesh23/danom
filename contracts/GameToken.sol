// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GameToken
 * @dev ERC20 token pegged to Monad at 1:100 ratio (1 MONAD = 100 GAME tokens)
 */
contract GameToken is ERC20, Ownable {
    uint256 public constant MONAD_TO_GAME_RATIO = 100; // 1 MONAD = 100 GAME tokens
    
    // Only authorized contracts can mint/burn
    mapping(address => bool) public authorizedMinters;
    
    event TokensMinted(address indexed user, uint256 monadAmount, uint256 gameTokenAmount);
    event TokensBurned(address indexed user, uint256 gameTokenAmount, uint256 monadAmount);
    event MinterAuthorized(address indexed minter);
    event MinterRevoked(address indexed minter);
    
    modifier onlyAuthorized() {
        require(authorizedMinters[msg.sender] || msg.sender == owner(), "Not authorized to mint/burn");
        _;
    }
    
    constructor() ERC20("Monad Game Token", "MGT") Ownable(msg.sender) {
        // Contract deployer becomes initial owner
    }
    
    /**
     * @dev Authorize a contract to mint/burn tokens (typically GameManager)
     */
    function authorizeMinter(address minter) external onlyOwner {
        authorizedMinters[minter] = true;
        emit MinterAuthorized(minter);
    }
    
    /**
     * @dev Revoke minting authorization
     */
    function revokeMinter(address minter) external onlyOwner {
        authorizedMinters[minter] = false;
        emit MinterRevoked(minter);
    }
    
    /**
     * @dev Mint tokens - only authorized contracts can call this
     */
    function mint(address to, uint256 amount) external onlyAuthorized {
        _mint(to, amount);
    }
    
    /**
     * @dev Burn tokens - only authorized contracts can call this
     */
    function burn(address from, uint256 amount) external onlyAuthorized {
        _burn(from, amount);
    }
    
    /**
     * @dev Convert Monad amount to Game Token amount
     */
    function monadToGameTokens(uint256 monadAmount) public pure returns (uint256) {
        return monadAmount * MONAD_TO_GAME_RATIO;
    }
    
    /**
     * @dev Convert Game Token amount to Monad amount
     */
    function gameTokensToMonad(uint256 gameTokenAmount) public pure returns (uint256) {
        return gameTokenAmount / MONAD_TO_GAME_RATIO;
    }
}