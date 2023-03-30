// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SneakerNFT is ERC721 {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    address private _owner;

    address private _mrcToken;
    uint256[] private _levelUpFees = [100, 200, 300, 400, 500];
    uint256[] private _levelZeroStakingRewards = [3, 7, 11, 14, 18];

    event NFTBought(uint256 indexed tokenId, address indexed buyer, uint256 price);
    event NFTForSale(uint256 indexed tokenId, address indexed seller, uint256 price);
    event NFTLevelUp(uint256 indexed tokenId, uint256 level);
    event Staked(address indexed from, uint256 indexed tokenId, uint256 stakingPeriod);
    event Unstaked(address indexed from, uint256 indexed tokenId, uint256 timeUnstaked);
    event UnstakeFeePaid(address indexed user, uint256 indexed tokenId);
    event RewardsClaimed(address indexed user, uint256 indexed tokenId, uint256 reward);

    enum Quality { Common, Uncommon, Rare, Epic, Legendary }
    enum Class { Walker, Jogger, Runner, Trainer}
    enum Rarity { FirstEdition }

    struct Sneaker {
        uint256 level;
        Quality quality;
        Class class;
        Rarity rarity;
    }

    struct Stake {
        uint256 stakedAt;
        uint256 stakedUntil;
        bool withdrawn;
    }

    uint256 public constant STAKING_DURATION_60DAYS = 60 days;
    uint256 public constant STAKING_DURATION_90DAYS = 90 days;
    uint256 public constant STAKING_DURATION_120DAYS = 120 days;
    uint256 public constant STAKING_DURATION_150DAYS = 150 days;
    uint256 public constant STAKING_DURATION_180DAYS = 180 days;

    uint256 private constant CLAIM_PERIOD = 1 days;

    uint256 public constant MAX_LEVEL = 30;

    uint256[] stakingDurations = [
        STAKING_DURATION_60DAYS,
        STAKING_DURATION_90DAYS,
        STAKING_DURATION_120DAYS,
        STAKING_DURATION_150DAYS,
        STAKING_DURATION_180DAYS
    ];

    mapping(uint256 => Sneaker) private _sneakers;
    mapping(uint256 => uint256) private nftPrice;
    mapping(address => mapping(uint256 => Stake)) public stakes;
    mapping(uint256 => uint256) private _stakingPeriods;
    mapping(address => uint256) public lastClaimedTime;

    modifier onlyOwner() {
        require(msg.sender == _owner, "Only the contract owner can perform this action.");
        _;
    }

    constructor() ERC721("SneakersNFT", "SNFT") {
        _owner = _msgSender();
    }

    // Get Trading Fee
    function getMrcToken() public view returns (address) {
        return _mrcToken;
    }

    // Set Tax Fee
    function setMrcToken(address address_) public onlyOwner {
        _mrcToken = address_;
    }

    // Mint NFT
    function mintSneaker() public returns (uint256) {
        uint256 newItemId = _tokenIds.current();
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender)));

        Quality quality = Quality(randomNumber % 5); 
        Class class = Class(randomNumber % 4); 
        Rarity rarity = Rarity(randomNumber % 1);

        Sneaker memory newSneaker = Sneaker(0, quality, class, rarity);
        _sneakers[newItemId] = newSneaker;
        _mint(msg.sender, newItemId);

        _tokenIds.increment();
        return newItemId;
    }

    // Buy NFT
    function buyNFT(uint256 tokenId) public payable {
        require(_exists(tokenId), "Invalid token ID");
        address owner = ownerOf(tokenId);
        require(owner != msg.sender, "You are the owner of this NFT");
        require(nftPrice[tokenId] == (msg.value),"");

        // Transfer the NFT to the buyer
        safeTransferFrom(owner, msg.sender, tokenId);

        // Send the payment to the seller
        payable(owner).transfer((msg.value * 94) /100);

        // Emit an event to signal the purchase
        emit NFTBought(tokenId, msg.sender, msg.value);
    }

    // Sell NFT
    function sellNFT(uint256 tokenId, uint256 price) public payable {
        uint256 sellerFee = (price * 6)/100;
        // Check that the seller owns the NFT
        require(ownerOf(tokenId) == msg.sender, "You do not own this NFT.");
        require(msg.value == sellerFee,"You need to pay enough selling Fees");

        // Transfer the 6% commission to the smart contract
        payable(address(this)).transfer(msg.value);

        // Approve the transfer of the NFT
        approve(address(this), tokenId);

        // Set the NFT price
        nftPrice[tokenId] = price;

        // Emit an event to signal the sale
        emit NFTForSale(tokenId,msg.sender, price);
    }

    // Level up NFT
    function levelUpNFT(uint256 tokenId) public {
        uint256 levelingUpFee = calculateLevelingUpFee(tokenId);
        require(_exists(tokenId), "Invalid token ID");
        Sneaker storage sneaker = _sneakers[tokenId];
        require(sneaker.level < MAX_LEVEL, "NFT is already at max level");
        require(IERC20(_mrcToken).allowance(msg.sender, address(this)) >= levelingUpFee, "Not enough tokens approved for transfer");
        require(IERC20(_mrcToken).balanceOf(msg.sender) >= levelingUpFee, "Not enough tokens in balance");

        // Transfer tokens from user to contract
        IERC20(_mrcToken).transferFrom(msg.sender, address(this), levelingUpFee);

        // Increase NFT level
        sneaker.level++;

        // Emit an event to signal the level up
        emit NFTLevelUp(tokenId, sneaker.level);
    }

    // Calculating the Leveling Up Fees
    function calculateLevelingUpFee(uint256 tokenId) public view returns (uint256) {
        require(_exists(tokenId), "Invalid token ID");
        Sneaker storage sneaker = _sneakers[tokenId];
        require(sneaker.level < MAX_LEVEL, "Sneaker has already reached maximum level");

        uint256 currentLevelFee = _levelUpFees[uint256(sneaker.quality)];
        uint256 nextLevelFee = currentLevelFee + (50 * sneaker.level);

        return nextLevelFee;
    }

    // Stake
    function stake(uint256 tokenId, uint256 stakingPeriod) external {
        require(stakes[msg.sender][tokenId].stakedUntil == 0, "Already staked");
        require(ownerOf(tokenId) == msg.sender, "Not owner");

        // Cheking the Staking Period
        bool validStakingPeriod = false;
        for (uint stakingDurationIndex = 0; stakingDurationIndex < stakingDurations.length; stakingDurationIndex++) {
            if (stakingDurations[stakingDurationIndex] == stakingPeriod) {
                validStakingPeriod = true;
                break;
            }
        }
        require(validStakingPeriod, "Invalid staking period");

        stakes[msg.sender][tokenId] = Stake(block.timestamp, block.timestamp + stakingPeriod, false);
        _stakingPeriods[tokenId] = stakingPeriod;

        // Approve the transfer of the NFT
        approve(address(this), tokenId);

        // Transfer the NFT to this Contract
        safeTransferFrom(msg.sender, address(this), tokenId);

        emit Staked(msg.sender, tokenId, stakingPeriod);
    }

    // Calculate Staking Reward
    function calculateStakingRewards(uint256 tokenId) public view returns (uint256){
        require(_exists(tokenId), "Invalid token ID");
        Sneaker storage sneaker = _sneakers[tokenId];
        uint256 stakingReward = 0;

        if (_stakingPeriods[tokenId] == 60) {
            stakingReward += _levelZeroStakingRewards[0] + sneaker.level;
        } else if (_stakingPeriods[tokenId] == 90) {
            stakingReward += _levelZeroStakingRewards[1] + sneaker.level;
        } else if (_stakingPeriods[tokenId] == 120) {
            stakingReward += _levelZeroStakingRewards[2] + sneaker.level;
        } else if (_stakingPeriods[tokenId] == 150) {
            stakingReward += _levelZeroStakingRewards[3] + sneaker.level;
        } else {
            stakingReward += _levelZeroStakingRewards[4] + sneaker.level;
        }

        return stakingReward;
    }


    function claimRewards(uint256 tokenId) external {
        require(_exists(tokenId), "Invalid token ID");
        require(block.timestamp >= lastClaimedTime[msg.sender] + CLAIM_PERIOD, "Cannot claim yet");

        // Check if the user has staked an NFT
        Stake memory stakedToken = stakes[msg.sender][tokenId];
        require(stakedToken.stakedAt > 0 && !stakedToken.withdrawn, "You have no stake to claim rewards for");

        // Check if the staking period has ended
        require(block.timestamp <= stakedToken.stakedUntil, "The staking period has ended");

        // Calculate the amount of rewards to be claimed
        uint256 rewards = calculateStakingRewards(tokenId);

        // Mark the stake as withdrawn
        stakes[msg.sender][tokenId].withdrawn = true;

        // Transfer the rewards to the user
        require(IERC20(_mrcToken).allowance(msg.sender, address(this)) >= rewards, "Not enough tokens approved for transfer");
        require(IERC20(_mrcToken).balanceOf(msg.sender) >= rewards, "Not enough tokens in balance");
        IERC20(_mrcToken).transfer(msg.sender, rewards);

        lastClaimedTime[msg.sender] = block.timestamp;
        emit RewardsClaimed(msg.sender, tokenId, rewards);
    }

    // Unstake NFT
    function unstake(uint256 tokenId) payable public {
        Stake storage userStake = stakes[msg.sender][tokenId];
        require(userStake.stakedUntil != 0, "You are not staking this NFT");
        require(block.timestamp >= userStake.stakedUntil, "Staking period not ended");

        // Check if the 
        if (block.timestamp < (userStake.stakedUntil) + CLAIM_PERIOD) {
            uint256 unstakingFee = 25e17 wei;
            require(msg.value >= unstakingFee, "Insufficient BNB Balance");
            emit UnstakeFeePaid (msg.sender,tokenId);
            
        }

        require(!userStake.withdrawn, "Already withdrawn");
        userStake.withdrawn = true;

        uint256 stakingPeriod = _stakingPeriods[tokenId];
        delete _stakingPeriods[tokenId];

        // Transfer the NFT back to the staker
        safeTransferFrom(address(this), msg.sender, tokenId);

        // Emit an event to signal the unstaking
        emit Unstaked(msg.sender, tokenId, stakingPeriod);
    }
}
