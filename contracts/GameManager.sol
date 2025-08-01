// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

// Import our custom contracts
interface IGameToken {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function monadToGameTokens(uint256 monadAmount) external pure returns (uint256);
    function gameTokensToMonad(uint256 gameTokenAmount) external pure returns (uint256);
}

interface IUserRegistry {
    function isUserValid(address user) external view returns (bool);
    function updateGameStats(address user, bool won, uint256 amount) external;
    function updateDepositStats(address user, uint256 amount, bool isDeposit) external;
}

/**
 * @title GameManager
 * @dev Main contract handling all game operations, deposits, and withdrawals
 */
contract GameManager is ReentrancyGuard, Ownable, Pausable {
    IGameToken public gameToken;
    IUserRegistry public userRegistry;
    
    // Platform settings
    uint256 public constant HOUSE_EDGE = 250; // 2.5% (in basis points)
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MONAD_TO_GAME_RATIO = 100;
    
    // Treasury for collected fees
    address public treasury;
    uint256 public totalFeesCollected;
    
    // Game types and their settings
    enum GameType { DICE, CARD, SKILL, SLOTS }
    
    struct GameConfig {
        uint256 minBet;      // Minimum bet in game tokens
        uint256 maxBet;      // Maximum bet in game tokens
        uint256 multiplier;  // Payout multiplier (in basis points) - what winner gets
        bool isActive;       // Is this game type active
        string name;         // Game name for frontend
    }
    
    mapping(GameType => GameConfig) public gameConfigs;
    mapping(address => uint256) public userBalances; // User game token balances
    
    // Platform statistics
    uint256 public totalGamesPlayed;
    uint256 public totalVolumeWagered;
    uint256 public totalPayouts;
    
    // Events
    event MonadDeposited(address indexed user, uint256 monadAmount, uint256 gameTokens);
    event GameTokensWithdrawn(address indexed user, uint256 gameTokens, uint256 monadAmount);
    event GamePlayed(
        address indexed user, 
        GameType gameType, 
        uint256 betAmount, 
        bool won, 
        uint256 payout,
        uint256 houseFee
    );
    event GameConfigUpdated(GameType gameType, GameConfig config);
    event HouseFeeCollected(uint256 amount);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event ContractsLinked(address gameToken, address userRegistry);
    
    constructor() Ownable(msg.sender) {
        treasury = msg.sender; // Initially set deployer as treasury
        
        // Initialize game configurations with default values
        gameConfigs[GameType.DICE] = GameConfig({
            minBet: 10 * 10**18,      // 10 game tokens minimum
            maxBet: 10000 * 10**18,   // 10,000 game tokens maximum  
            multiplier: 19000,        // 1.9x payout (after house edge)
            isActive: true,
            name: "Dice Game"
        });
        
        gameConfigs[GameType.CARD] = GameConfig({
            minBet: 50 * 10**18,      // 50 game tokens minimum
            maxBet: 5000 * 10**18,    // 5,000 game tokens maximum
            multiplier: 18000,        // 1.8x payout
            isActive: true,
            name: "Card Game"
        });
        
        gameConfigs[GameType.SKILL] = GameConfig({
            minBet: 100 * 10**18,     // 100 game tokens minimum
            maxBet: 20000 * 10**18,   // 20,000 game tokens maximum
            multiplier: 19500,        // 1.95x payout
            isActive: true,
            name: "Skill Game"
        });
        
        gameConfigs[GameType.SLOTS] = GameConfig({
            minBet: 5 * 10**18,       // 5 game tokens minimum
            maxBet: 1000 * 10**18,    // 1,000 game tokens maximum
            multiplier: 17500,        // 1.75x payout
            isActive: true,
            name: "Slots"
        });
    }
    
    /**
     * @dev Link the GameToken and UserRegistry contracts (call this after deployment)
     */
    function linkContracts(address _gameToken, address _userRegistry) external onlyOwner {
        require(_gameToken != address(0), "Invalid GameToken address");
        require(_userRegistry != address(0), "Invalid UserRegistry address");
        
        gameToken = IGameToken(_gameToken);
        userRegistry = IUserRegistry(_userRegistry);
        
        emit ContractsLinked(_gameToken, _userRegistry);
    }
    
    // =============================================================================
    // DEPOSIT & WITHDRAWAL FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Deposit Monad and receive game tokens (1 MONAD = 100 game tokens)
     */
    function depositMonad() external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "Must deposit some Monad");
        require(address(gameToken) != address(0), "GameToken not linked");
        
        // Check if user is registered (if UserRegistry is linked)
        if (address(userRegistry) != address(0)) {
            require(userRegistry.isUserValid(msg.sender), "User not registered or banned");
        }
        
        uint256 gameTokensToMint = gameToken.monadToGameTokens(msg.value);
        
        // Mint game tokens to this contract
        gameToken.mint(address(this), gameTokensToMint);
        
        // Add to user's balance
        userBalances[msg.sender] += gameTokensToMint;
        
        // Update user stats if registry is linked
        if (address(userRegistry) != address(0)) {
            userRegistry.updateDepositStats(msg.sender, msg.value, true);
        }
        
        emit MonadDeposited(msg.sender, msg.value, gameTokensToMint);
    }
    
    /**
     * @dev Withdraw game tokens back to Monad (100 game tokens = 1 MONAD)
     */
    function withdrawToMonad(uint256 gameTokenAmount) external nonReentrant whenNotPaused {
        require(gameTokenAmount > 0, "Amount must be greater than 0");
        require(userBalances[msg.sender] >= gameTokenAmount, "Insufficient balance");
        require(gameTokenAmount % MONAD_TO_GAME_RATIO == 0, "Amount must be divisible by 100");
        require(address(gameToken) != address(0), "GameToken not linked");
        
        uint256 monadToWithdraw = gameToken.gameTokensToMonad(gameTokenAmount);
        require(address(this).balance >= monadToWithdraw, "Insufficient contract balance");
        
        // Check if user is valid (if UserRegistry is linked)
        if (address(userRegistry) != address(0)) {
            require(userRegistry.isUserValid(msg.sender), "User not registered or banned");
        }
        
        // Deduct from user balance
        userBalances[msg.sender] -= gameTokenAmount;
        
        // Burn the game tokens
        gameToken.burn(address(this), gameTokenAmount);
        
        // Transfer Monad to user
        payable(msg.sender).transfer(monadToWithdraw);
        
        // Update user stats if registry is linked
        if (address(userRegistry) != address(0)) {
            userRegistry.updateDepositStats(msg.sender, monadToWithdraw, false);
        }
        
        emit GameTokensWithdrawn(msg.sender, gameTokenAmount, monadToWithdraw);
    }
    
    // =============================================================================
    // GAME FUNCTIONS
    // =============================================================================
    
    /**
     * @dev Play a game - called by frontend after determining win/loss
     */
    function playGame(
        GameType gameType, 
        uint256 betAmount, 
        bool userWon
    ) external nonReentrant whenNotPaused {
        GameConfig memory config = gameConfigs[gameType];
        require(config.isActive, "Game type not active");
        require(betAmount >= config.minBet, "Bet below minimum");
        require(betAmount <= config.maxBet, "Bet exceeds maximum");
        require(userBalances[msg.sender] >= betAmount, "Insufficient balance");
        
        // Check if user is valid (if UserRegistry is linked)
        if (address(userRegistry) != address(0)) {
            require(userRegistry.isUserValid(msg.sender), "User not registered or banned");
        }
        
        // Deduct bet amount from user balance
        userBalances[msg.sender] -= betAmount;
        
        uint256 payout = 0;
        uint256 houseFee = (betAmount * HOUSE_EDGE) / BASIS_POINTS;
        
        if (userWon) {
            // Calculate payout (bet amount * multiplier)
            payout = (betAmount * config.multiplier) / BASIS_POINTS;
            
            // Ensure contract has enough balance for payout
            require(gameToken.balanceOf(address(this)) >= payout, "Insufficient contract balance for payout");
            
            // Add payout to user balance
            userBalances[msg.sender] += payout;
            totalPayouts += payout;
        }
        
        // Collect house fee
        totalFeesCollected += houseFee;
        
        // Update platform statistics
        totalGamesPlayed++;
        totalVolumeWagered += betAmount;
        
        // Update user stats if registry is linked
        if (address(userRegistry) != address(0)) {
            userRegistry.updateGameStats(msg.sender, userWon, userWon ? payout : betAmount);
        }
        
        emit GamePlayed(msg.sender, gameType, betAmount, userWon, payout, houseFee);
        emit HouseFeeCollected(houseFee);
    }
    
    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================
    
    function getUserBalance(address user) external view returns (uint256) {
        return userBalances[user];
    }
    
    function getGameConfig(GameType gameType) external view returns (GameConfig memory) {
        return gameConfigs[gameType];
    }
    
    function getAllGameConfigs() external view returns (GameConfig[4] memory) {
        return [
            gameConfigs[GameType.DICE],
            gameConfigs[GameType.CARD], 
            gameConfigs[GameType.SKILL],
            gameConfigs[GameType.SLOTS]
        ];
    }
    
    function getContractMonadBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    function getContractGameTokenBalance() external view returns (uint256) {
        return gameToken.balanceOf(address(this));
    }
    
    function getPlatformStats() external view returns (
        uint256 _totalGamesPlayed,
        uint256 _totalVolumeWagered,
        uint256 _totalPayouts,
        uint256 _totalFeesCollected,
        uint256 contractMonadBalance,
        uint256 contractTokenBalance
    ) {
        return (
            totalGamesPlayed,
            totalVolumeWagered,
            totalPayouts,
            totalFeesCollected,
            address(this).balance,
            address(gameToken) != address(0) ? gameToken.balanceOf(address(this)) : 0
        );
    }
    
    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================
    
    function updateGameConfig(
        GameType gameType,
        uint256 minBet,
        uint256 maxBet,
        uint256 multiplier,
        bool isActive,
        string calldata name
    ) external onlyOwner {
        gameConfigs[gameType] = GameConfig({
            minBet: minBet,
            maxBet: maxBet,
            multiplier: multiplier,
            isActive: isActive,
            name: name
        });
        
        emit GameConfigUpdated(gameType, gameConfigs[gameType]);
    }
    
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury address");
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }
    
    function withdrawFees() external onlyOwner {
        require(treasury != address(0), "Treasury not set");
        uint256 feesToWithdraw = totalFeesCollected;
        require(feesToWithdraw > 0, "No fees to withdraw");
        
        totalFeesCollected = 0;
        
        // Calculate equivalent Monad amount for the fees (fees are in game tokens conceptually)
        uint256 monadAmount = gameToken.gameTokensToMonad(feesToWithdraw);
        require(address(this).balance >= monadAmount, "Insufficient contract balance");
        
        payable(treasury).transfer(monadAmount);
    }
    
    function emergencyWithdrawMonad(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient balance");
        payable(owner()).transfer(amount);
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // Receive function to accept Monad deposits directly
    receive() external payable {
        // Direct Monad deposits (for liquidity/manual funding)
    }
}