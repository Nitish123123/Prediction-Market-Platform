// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Prediction Market Platform
 * @dev A decentralized prediction market contract where users can create markets,
 * place bets on binary outcomes, and claim winnings based on resolved results.
 * @author Prediction Market Team
 * @notice This contract allows users to create prediction markets and place bets
 */
contract Project {
    
    // Struct to represent a prediction market
    struct Market {
        uint256 id;
        string question;
        string category;
        uint256 endTime;
        uint256 totalYesAmount;
        uint256 totalNoAmount;
        bool resolved;
        bool outcome; // true = YES wins, false = NO wins
        address creator;
        uint256 createdAt;
    }
    
    // Struct to represent a user's bet
    struct Bet {
        uint256 marketId;
        address bettor;
        bool prediction; // true = YES, false = NO
        uint256 amount;
        bool claimed;
    }
    
    // State variables
    uint256 public marketCounter;
    uint256 public constant PLATFORM_FEE = 2; // 2% platform fee
    address public owner;
    
    // Mappings
    mapping(uint256 => Market) public markets;
    mapping(uint256 => Bet[]) public marketBets;
    mapping(address => uint256[]) public userMarkets;
    mapping(address => mapping(uint256 => uint256[])) public userBets; // user => marketId => bet indices
    
    // Events
    event MarketCreated(uint256 indexed marketId, string question, address indexed creator, uint256 endTime);
    event BetPlaced(uint256 indexed marketId, address indexed bettor, bool prediction, uint256 amount);
    event MarketResolved(uint256 indexed marketId, bool outcome, uint256 totalPool);
    event WinningsClaimed(uint256 indexed marketId, address indexed winner, uint256 amount);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier marketExists(uint256 _marketId) {
        require(_marketId > 0 && _marketId <= marketCounter, "Market does not exist");
        _;
    }
    
    modifier marketActive(uint256 _marketId) {
        require(block.timestamp < markets[_marketId].endTime, "Market has ended");
        require(!markets[_marketId].resolved, "Market already resolved");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        marketCounter = 0;
    }
    
    /**
     * @dev Core Function 1: Create a new prediction market
     * @param _question The question for the prediction market
     * @param _category Category of the market (e.g., "Sports", "Politics", "Crypto")
     * @param _duration Duration in seconds from now until market ends
     */
    function createMarket(
        string memory _question,
        string memory _category,
        uint256 _duration
    ) external {
        require(bytes(_question).length > 0, "Question cannot be empty");
        require(_duration > 0, "Duration must be positive");
        require(_duration <= 365 days, "Duration cannot exceed 1 year");
        
        marketCounter++;
        uint256 endTime = block.timestamp + _duration;
        
        markets[marketCounter] = Market({
            id: marketCounter,
            question: _question,
            category: _category,
            endTime: endTime,
            totalYesAmount: 0,
            totalNoAmount: 0,
            resolved: false,
            outcome: false,
            creator: msg.sender,
            createdAt: block.timestamp
        });
        
        userMarkets[msg.sender].push(marketCounter);
        
        emit MarketCreated(marketCounter, _question, msg.sender, endTime);
    }
    
    /**
     * @dev Core Function 2: Place a bet on a prediction market
     * @param _marketId ID of the market to bet on
     * @param _prediction User's prediction (true = YES, false = NO)
     */
    function placeBet(uint256 _marketId, bool _prediction) 
        external 
        payable 
        marketExists(_marketId) 
        marketActive(_marketId) 
    {
        require(msg.value > 0, "Bet amount must be greater than 0");
        require(msg.value >= 0.001 ether, "Minimum bet is 0.001 ETH");
        
        Market storage market = markets[_marketId];
        
        // Update market totals
        if (_prediction) {
            market.totalYesAmount += msg.value;
        } else {
            market.totalNoAmount += msg.value;
        }
        
        // Create bet record
        Bet memory newBet = Bet({
            marketId: _marketId,
            bettor: msg.sender,
            prediction: _prediction,
            amount: msg.value,
            claimed: false
        });
        
        marketBets[_marketId].push(newBet);
        userBets[msg.sender][_marketId].push(marketBets[_marketId].length - 1);
        
        emit BetPlaced(_marketId, msg.sender, _prediction, msg.value);
    }
    
    /**
     * @dev Core Function 3: Resolve market and distribute winnings
     * @param _marketId ID of the market to resolve
     * @param _outcome The actual outcome (true = YES wins, false = NO wins)
     */
    function resolveMarket(uint256 _marketId, bool _outcome) 
        external 
        onlyOwner 
        marketExists(_marketId) 
    {
        Market storage market = markets[_marketId];
        require(block.timestamp >= market.endTime, "Market has not ended yet");
        require(!market.resolved, "Market already resolved");
        
        market.resolved = true;
        market.outcome = _outcome;
        
        uint256 totalPool = market.totalYesAmount + market.totalNoAmount;
        
        emit MarketResolved(_marketId, _outcome, totalPool);
    }
    
    /**
     * @dev Claim winnings for a resolved market
     * @param _marketId ID of the resolved market
     */
    function claimWinnings(uint256 _marketId) 
        external 
        marketExists(_marketId) 
    {
        Market storage market = markets[_marketId];
        require(market.resolved, "Market not resolved yet");
        
        uint256[] storage userBetIndices = userBets[msg.sender][_marketId];
        require(userBetIndices.length > 0, "No bets found for this market");
        
        uint256 totalWinnings = 0;
        uint256 totalPool = market.totalYesAmount + market.totalNoAmount;
        uint256 winningPool = market.outcome ? market.totalYesAmount : market.totalNoAmount;
        
        for (uint256 i = 0; i < userBetIndices.length; i++) {
            Bet storage bet = marketBets[_marketId][userBetIndices[i]];
            
            if (!bet.claimed && bet.prediction == market.outcome) {
                // Calculate proportional winnings
                uint256 winnings = (bet.amount * totalPool) / winningPool;
                uint256 platformFee = (winnings * PLATFORM_FEE) / 100;
                uint256 netWinnings = winnings - platformFee;
                
                totalWinnings += netWinnings;
                bet.claimed = true;
            }
        }
        
        require(totalWinnings > 0, "No winnings to claim");
        
        payable(msg.sender).transfer(totalWinnings);
        
        emit WinningsClaimed(_marketId, msg.sender, totalWinnings);
    }
    
    // View functions
    function getMarket(uint256 _marketId) 
        external 
        view 
        marketExists(_marketId) 
        returns (Market memory) 
    {
        return markets[_marketId];
    }
    
    function getMarketBets(uint256 _marketId) 
        external 
        view 
        marketExists(_marketId) 
        returns (Bet[] memory) 
    {
        return marketBets[_marketId];
    }
    
    function getUserMarkets(address _user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return userMarkets[_user];
    }
    
    function getUserBetsInMarket(address _user, uint256 _marketId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return userBets[_user][_marketId];
    }
    
    function getMarketOdds(uint256 _marketId) 
        external 
        view 
        marketExists(_marketId) 
        returns (uint256 yesOdds, uint256 noOdds) 
    {
        Market storage market = markets[_marketId];
        uint256 totalPool = market.totalYesAmount + market.totalNoAmount;
        
        if (totalPool == 0) {
            return (50, 50); // 50-50 odds if no bets placed
        }
        
        yesOdds = (market.totalYesAmount * 100) / totalPool;
        noOdds = (market.totalNoAmount * 100) / totalPool;
    }
    
    // Owner functions
    function withdrawPlatformFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        payable(owner).transfer(balance);
    }
    
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid address");
        owner = _newOwner;
    }
    
    // Emergency function
    function emergencyPause() external onlyOwner {
        // In a real implementation, this would pause all contract functions
        // For simplicity, we're just emitting an event
        // emit EmergencyPause(block.timestamp);
    }
    
    // Receive function to accept ETH
    receive() external payable {}
}
