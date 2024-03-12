// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.5.0/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.5.0/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.5.0/contracts/utils/Counters.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.5.0/contracts/access/Ownable.sol";
import "./RewardToken.sol";

contract TamagotchiERC is ERC721Enumerable, ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    RewardToken public rewardToken;
    mapping(uint256 => uint256) public tokenMintTimestamps;
    mapping(uint256 => uint256) public claimCounts;
    mapping(uint256 => string) private _evolvedURIs;
    mapping(uint256 => bool) public hasEvolved;

    string private _baseTokenURI;
    uint256 public evolvedCount;
    uint256 public HOLDING_PERIOD = 6 hours; 
    uint256 public constant REWARD_AMOUNT = 100 * (10 ** 18);
    uint256 public constant EVOLVED_REWARD_AMOUNT = 300 * (10 ** 18);
    uint256 public constant BASE_EVOLUTION_THRESHOLD = 5;    
    uint256 public constant MAX_EXTRA_THRESHOLD = 3; 

    uint256 public constant MINT_PRICE = 0.02 ether;
    uint256 public constant MAX_MINT_PER_WALLET = 100;
    uint256 public constant MAX_MINT_AT_ONCE = 20;
    uint256 public constant MAX_SUPPLY = 5000;
    mapping(address => uint256) public mintedPerWallet;

    constructor(address _rewardTokenAddress, string memory baseTokenURI) ERC721("Virtual Pets", "VPET") Ownable() {
        rewardToken = RewardToken(_rewardTokenAddress);
        _baseTokenURI = baseTokenURI;
    }

    function setBaseTokenURI(string memory baseTokenURI) public onlyOwner {
        _baseTokenURI = baseTokenURI;
    }

    function mintNFT(uint256 quantity) public payable {
        require(quantity > 0 && quantity <= MAX_MINT_AT_ONCE, "Cannot mint specified number at once");
        require(mintedPerWallet[msg.sender] + quantity <= MAX_MINT_PER_WALLET, "Exceeds maximum per wallet");
        require(msg.value >= MINT_PRICE * quantity, "Ether sent is not correct");
        require(_tokenIdCounter.current() + quantity <= MAX_SUPPLY, "Exceeds maximum supply");
        
        for (uint256 i = 0; i < quantity; i++) {
            _tokenIdCounter.increment();
            uint256 tokenId = _tokenIdCounter.current();
            _mint(msg.sender, tokenId);
            tokenMintTimestamps[tokenId] = block.timestamp;
            claimCounts[tokenId] = 0;
        }

        mintedPerWallet[msg.sender] += quantity; 
    }



    function claimAllRewards() public nonReentrant {
        uint256 ownerTokenCount = balanceOf(msg.sender);
        require(ownerTokenCount > 0, "No NFTs owned.");

        uint256 totalReward = 0;

        for (uint256 i = 0; i < ownerTokenCount; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(msg.sender, i);
            if (block.timestamp >= tokenMintTimestamps[tokenId] + HOLDING_PERIOD) {
                tokenMintTimestamps[tokenId] = block.timestamp;
                totalReward += REWARD_AMOUNT;
                claimCounts[tokenId] += 1;

                if (claimCounts[tokenId] >= calculateEvolutionThreshold(tokenId)) {
                    evolve(tokenId);
                }
            }
        }

        require(totalReward > 0, "No rewards available to claim.");
        bool sent = rewardToken.transfer(msg.sender, totalReward);
        require(sent, "Reward token transfer failed.");
    }


    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override {
        super._beforeTokenTransfer(from, to, tokenId); // Call parent hook
        if (from != address(0) && to != address(0) && !hasEvolved[tokenId]) {
            // Only reset claim counts if the NFT hasn't evolved
            claimCounts[tokenId] = 0;
        }
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        if (bytes(_evolvedURIs[tokenId]).length > 0) {
            return _evolvedURIs[tokenId];
        }

        return string(abi.encodePacked(_baseTokenURI, Strings.toString(tokenId)));
    }

    function calculateEvolutionThreshold(uint256 tokenId) public view returns (uint256) {
        // Generate a pseudo-random number based on the hash of the token ID and current block characteristics, using block.prevrandao for randomness
        uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, tokenId))) % (MAX_EXTRA_THRESHOLD + 1);
        return BASE_EVOLUTION_THRESHOLD + random;
    }

    function evolve(uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender, "Caller is not the owner");
        uint256 evolutionThreshold = calculateEvolutionThreshold(tokenId);
        require(claimCounts[tokenId] >= evolutionThreshold, "Not enough claims to evolve");
        
        string memory evolvedURI = string(abi.encodePacked("https://nftmetadata/", Strings.toString(tokenId), ".json"));
        _evolvedURIs[tokenId] = evolvedURI;
        hasEvolved[tokenId] = true; // Mark the NFT as evolved
        
        evolvedCount += 1; // Increment the count of evolved NFTs
        
      
        if (evolvedCount == 800 || evolvedCount == 1600 || evolvedCount == 2400) {
            HOLDING_PERIOD += 6 hours;
        }
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No Ether left to withdraw");
        (bool sent, ) = owner().call{value: balance}("");
        require(sent, "Failed to send Ether");
    }

}
