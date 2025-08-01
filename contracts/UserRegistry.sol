// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title UserRegistry
 * @dev Manages user registration, statistics, and access control
 */
contract UserRegistry is Ownable {
    struct User {
        bool isRegistered;
        uint256 registrationTime;
        uint256 totalGamesPlayed;
        uint256 totalWon;
        uint256 totalLost;
        uint256 totalDeposited;
        uint256 totalWithdrawn;
    }
    
    mapping(address => User) public users;
    mapping(address => bool) public bannedUsers;
    mapping(address => bool) public authorizedGameManagers; // Multiple game managers can be authorized
    
    uint256 public totalRegisteredUsers;
    
    event UserRegistered(address indexed user, uint256 timestamp);
    event UserBanned(address indexed user, string reason);
    event UserUnbanned(address indexed user);
    event GameManagerAuthorized(address indexed gameManager);
    event GameManagerRevoked(address indexed gameManager);
    event UserStatsUpdated(address indexed user, bool won, uint256 amount);
    
    modifier onlyRegistered() {
        require(users[msg.sender].isRegistered, "User not registered");
        require(!bannedUsers[msg.sender], "User is banned");
        _;
    }
    
    modifier onlyAuthorizedGameManager() {
        require(authorizedGameManagers[msg.sender], "Not authorized game manager");
        _;
    }
    
    constructor() Ownable(msg.sender) {
        // Contract deployer becomes initial owner
    }
    
    /**
     * @dev Authorize a GameManager contract to update user stats
     */
    function authorizeGameManager(address gameManager) external onlyOwner {
        authorizedGameManagers[gameManager] = true;
        emit GameManagerAuthorized(gameManager);
    }
    
    /**
     * @dev Revoke GameManager authorization
     */
    function revokeGameManager(address gameManager) external onlyOwner {
        authorizedGameManagers[gameManager] = false;
        emit GameManagerRevoked(gameManager);
    }
    
    /**
     * @dev Register a new user
     */
    function registerUser() external {
        require(!users[msg.sender].isRegistered, "User already registered");
        require(!bannedUsers[msg.sender], "User is banned");
        
        users[msg.sender] = User({
            isRegistered: true,
            registrationTime: block.timestamp,
            totalGamesPlayed: 0,
            totalWon: 0,
            totalLost: 0,
            totalDeposited: 0,
            totalWithdrawn: 0
        });
        
        totalRegisteredUsers++;
        emit UserRegistered(msg.sender, block.timestamp);
    }
    
    /**
     * @dev Update user game statistics - only authorized GameManager can call
     */
    function updateGameStats(address user, bool won, uint256 amount) external onlyAuthorizedGameManager {
        require(users[user].isRegistered, "User not registered");
        
        users[user].totalGamesPlayed++;
        if (won) {
            users[user].totalWon += amount;
        } else {
            users[user].totalLost += amount;
        }
        
        emit UserStatsUpdated(user, won, amount);
    }
    
    /**
     * @dev Update user deposit/withdrawal statistics
     */
    function updateDepositStats(address user, uint256 amount, bool isDeposit) external onlyAuthorizedGameManager {
        require(users[user].isRegistered, "User not registered");
        
        if (isDeposit) {
            users[user].totalDeposited += amount;
        } else {
            users[user].totalWithdrawn += amount;
        }
    }
    
    /**
     * @dev Ban a user with reason
     */
    function banUser(address user, string calldata reason) external onlyOwner {
        bannedUsers[user] = true;
        emit UserBanned(user, reason);
    }
    
    /**
     * @dev Unban a user
     */
    function unbanUser(address user) external onlyOwner {
        bannedUsers[user] = false;
        emit UserUnbanned(user);
    }
    
    /**
     * @dev Check if user is registered and not banned
     */
    function isUserValid(address user) external view returns (bool) {
        return users[user].isRegistered && !bannedUsers[user];
    }
    
    /**
     * @dev Get user statistics - split into two functions to avoid stack too deep
     */
    function getUserStats(address user) external view returns (
        bool isRegistered,
        uint256 registrationTime,
        uint256 totalGamesPlayed,
        bool isBanned
    ) {
        User storage userData = users[user];
        return (
            userData.isRegistered,
            userData.registrationTime,
            userData.totalGamesPlayed,
            bannedUsers[user]
        );
    }
    
    /**
     * @dev Get user financial statistics
     */
    function getUserFinancialStats(address user) external view returns (
        uint256 totalWon,
        uint256 totalLost,
        uint256 totalDeposited,
        uint256 totalWithdrawn
    ) {
        User storage userData = users[user];
        return (
            userData.totalWon,
            userData.totalLost,
            userData.totalDeposited,
            userData.totalWithdrawn
        );
    }
    
    /**
     * @dev Get user's win rate (returns percentage * 100, e.g., 7500 = 75%)
     */
    function getUserWinRate(address user) external view returns (uint256) {
        User memory userData = users[user];
        if (userData.totalGamesPlayed == 0) return 0;
        
        uint256 wins = userData.totalWon > 0 ? userData.totalGamesPlayed - (userData.totalLost / (userData.totalWon + userData.totalLost) * userData.totalGamesPlayed) : 0;
        return (wins * 10000) / userData.totalGamesPlayed;
    }
    
    /**
     * @dev Get platform statistics
     */
    function getPlatformStats() external view returns (
        uint256 _totalRegisteredUsers,
        uint256 totalGamesPlayedPlatform,
        uint256 totalVolume
    ) {
        // Note: For gas efficiency, platform-wide stats would need to be tracked separately
        // This is a basic implementation
        return (totalRegisteredUsers, 0, 0);
    }
}