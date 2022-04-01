// SPDX-License-Identifier: None
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

import "./DefiMinerNFT.sol";
import "../util/interfaces/subscriber/ShopSubscriber.sol";
import "../util/interfaces/subscriber/Subscribable.sol";
import "../util/Whitelist.sol";

/// @title The codebase for the NFT shop used at MinerBox DApp.
/// @author Lukas Jonsson
/// @notice The owner of this contract can create nft batches. NFT Batches allow customers to mint an nft for an actual price.
/// @dev This contract extends the Subscribable code base which allows the owner to add a subscriber. The Shop calls subscriber functions on createBatch and on mint.

contract NFTShop is Subscribable {
    // ## Structs ##
    //TODO: Reorganize struct -> Storage efficiency
    struct NFT_Batch {
        uint256 creationTimestamp;
        DefiMinerNFT nft;
        ERC20 priceToken;
        uint256 pricePerNFT;
        uint256 maxSellAmount;
        uint256 alreadySold;
        address treasuryAddress;
        string description;
        bool exist;
        uint256 limitPerCustomer;
        Whitelist whitelist;
        bool usesWhitelist;
    }

    // ## Variables ##

    // Stores the info about every nft batch that currently exists for a certain nft.
    mapping(DefiMinerNFT => NFT_Batch) nftBatches;
    // Stores the amount of NFTs bought per wallet.
    mapping(uint256 => mapping(address => uint256)) alreadyBought;
    // Stores the amount of NFTs gifted
    mapping(DefiMinerNFT => uint256) gifted;

    // ## Constructors ##

    constructor(ProjectOwnership _ownership) Subscribable(_ownership) {}

    // ## Events ##

    event NFTBatchCreated(
        DefiMinerNFT _nft,
        ERC20 indexed _priceToken,
        uint256 indexed _pricePerNFT,
        uint256 _maxSellAmount,
        uint256 _alreadySold,
        address indexed _treasuryAddress,
        string _description
    );

    event NFTMint(
        address indexed buyer,
        DefiMinerNFT indexed _nft,
        ERC20 _priceToken,
        uint256 _price,
        address indexed treasuryAddress
    );

    event NFTGifted(address receiver, DefiMinerNFT _nft, uint256 amount);

    // ## External functions ##

    /// @notice Same as createNFTBatch but requires a whitelist as additional parameter.
    function createWhitelistedNFTBatch(
        DefiMinerNFT _nft,
        ERC20 _priceToken,
        uint256 _pricePerNFT,
        uint256 _maxSellAmount,
        uint256 _alreadySold,
        address _treasuryAddress,
        string memory _description,
        uint256 _limitPerCustomer,
        Whitelist _whitelist
    ) external onlyProject {
        _createNFTBatch(
            _nft,
            _priceToken,
            _pricePerNFT,
            _maxSellAmount,
            _alreadySold,
            _treasuryAddress,
            _description,
            _limitPerCustomer,
            _whitelist
        );
    }

    /// @notice Creates a NFT Batch for a certain NFT.
    function createNFTBatch(
        DefiMinerNFT _nft,
        ERC20 _priceToken,
        uint256 _pricePerNFT,
        uint256 _maxSellAmount,
        uint256 _alreadySold,
        address _treasuryAddress,
        string memory _description,
        uint256 _limitPerCustomer
    ) external onlyProject {
        _createNFTBatch(
            _nft,
            _priceToken,
            _pricePerNFT,
            _maxSellAmount,
            _alreadySold,
            _treasuryAddress,
            _description,
            _limitPerCustomer,
            Whitelist(address(0))
        );
    }

    /// @notice Used to delete a batch for a certain nft
    /// @dev normally you could just change most of the variables of a batch but if needed this function also exists.
    //TODO: Requires testing since gifting limit change
    function deleteBatch(DefiMinerNFT _nft) external onlyProject {
        requireBatchExist(_nft);
        delete (nftBatches[_nft]);
    }

    /// @notice triggered by a user to mint the nft for a certain price
    function mintNFT(DefiMinerNFT _nft) external {
        requireBatchExist(_nft);
        NFT_Batch storage batch = nftBatches[_nft];
        require(
            batch.priceToken.allowance(msg.sender, address(this)) >=
                batch.pricePerNFT,
            "Shop: Price token not approved."
        );
        require(
            batch.priceToken.balanceOf(msg.sender) >= batch.pricePerNFT,
            "Shop: Not enough funds to buy NFT."
        );
        require(
            batch.alreadySold < batch.maxSellAmount,
            "Shop: This Batch is sold out."
        );
        if (batch.usesWhitelist)
            require(
                batch.whitelist.getWhitelistStatus(msg.sender),
                "Shop: You are not on the whitelist for this NFT Batch."
            );
        if (batch.limitPerCustomer > 0) {
            require(
                alreadyBought[batch.creationTimestamp][msg.sender] <
                    batch.limitPerCustomer,
                "Shop: You have already bought the maximum allowed amount of NFTs in this batch."
            );
            alreadyBought[batch.creationTimestamp][msg.sender] += 1;
        }
        batch.alreadySold++;

        uint256 tokenID = _nft.getNextTokenID();
        for (uint256 i = 0; i < subscribers.length; i++) {
            ShopSubscriber sub = ShopSubscriber(address(subscribers[i]));
            sub.onNFTMint(_nft, tokenID);
        }

        emit NFTMint(
            msg.sender,
            _nft,
            batch.priceToken,
            batch.pricePerNFT,
            batch.treasuryAddress
        );

        bool result = batch.priceToken.transferFrom(
            msg.sender,
            batch.treasuryAddress,
            batch.pricePerNFT
        );
        assert(result);
        _nft.safeMint(msg.sender);
    }

    /// @notice allows to gift an NFT to a certain wallet address
    //TODO: Requires testing
    function giftNFT(
        DefiMinerNFT _nft,
        address minter,
        uint256 amount
    ) external onlyProject {
        requireBatchExist(_nft);
        NFT_Batch storage batch = nftBatches[_nft];
        require(
            gifted[_nft] + amount <= _nft.getGiftLimit(),
            "Shop: Gifting limit reached."
        );
        require(
            batch.alreadySold < batch.maxSellAmount,
            "Shop: This Batch is sold out."
        );

        batch.alreadySold += amount;

        uint256 tokenID = _nft.getNextTokenID();
        for (uint256 i = 0; i < subscribers.length; i++) {
            ShopSubscriber sub = ShopSubscriber(address(subscribers[i]));
            sub.onNFTGift(_nft, tokenID, amount);
        }

        gifted[_nft] += amount;

        emit NFTGifted(msg.sender, _nft, amount);

        for (uint256 i = 0; i < amount; i++) {
            _nft.safeMint(minter);
        }
    }

    // Setter Functions for nft Batches

    /// @notice allows to change the price token of an nft batch
    function setPriceToken(DefiMinerNFT _nft, ERC20 _newPriceToken)
        external
        onlyProject
    {
        requireBatchExist(_nft);
        NFT_Batch storage batch = nftBatches[_nft];
        batch.priceToken = _newPriceToken;
    }

    /// @notice allows to change the price of an nft batch
    function setPrice(DefiMinerNFT _nft, uint256 _newPrice)
        external
        onlyProject
    {
        requireBatchExist(_nft);
        NFT_Batch storage batch = nftBatches[_nft];
        batch.pricePerNFT = _newPrice;
    }

    /// @notice allows to change the maxSellAmount of an nft batch
    function setMaxSellAmount(DefiMinerNFT _nft, uint256 _newMaxSellAmount)
        external
        onlyProject
    {
        requireBatchExist(_nft);
        NFT_Batch storage batch = nftBatches[_nft];
        batch.maxSellAmount = _newMaxSellAmount;
    }

    /// @notice allows to change the treasuryAddress of an nft batch
    function setTreasuryAddress(DefiMinerNFT _nft, address _treasuryAddress)
        external
        onlyProject
    {
        requireBatchExist(_nft);
        NFT_Batch storage batch = nftBatches[_nft];
        batch.treasuryAddress = _treasuryAddress;
    }

    /// @notice allows to change the limit per customer of an nft batch
    function setLimitPerCustomer(
        DefiMinerNFT _nft,
        uint256 _newLimitPerCustomer
    ) external onlyProject {
        requireBatchExist(_nft);
        NFT_Batch storage batch = nftBatches[_nft];
        batch.limitPerCustomer = _newLimitPerCustomer;
    }

    /// @notice allows to change the description of an nft batch
    function setDescription(DefiMinerNFT _nft, string memory _description)
        external
        onlyProject
    {
        requireBatchExist(_nft);
        NFT_Batch storage batch = nftBatches[_nft];
        batch.description = _description;
    }

    /// @notice allows to change the whitelist contract of an nft batch
    function setWhitelist(DefiMinerNFT _nft, Whitelist whitelist)
        external
        onlyProject
    {
        requireBatchExist(_nft);
        NFT_Batch storage batch = nftBatches[_nft];
        batch.whitelist = whitelist;
    }

    /// @notice allows to change whether to use the whitelist contract of an nft batch
    function setWhitelistStatus(DefiMinerNFT _nft, bool value)
        external
        onlyProject
    {
        requireBatchExist(_nft);
        NFT_Batch storage batch = nftBatches[_nft];
        batch.usesWhitelist = value;
    }

    // ### View Functions ###

    /// @return nftBatch the stored information of an existing nft batch.
    /// @return priceName name of the priceToken
    /// @return priceSymbol symbol of the priceToken
    /// @return nftName of the NFT
    /// @return nftSymbol symbol of the NFT
    function getBatch(DefiMinerNFT _nft)
        external
        view
        returns (
            NFT_Batch memory nftBatch,
            string memory priceName,
            string memory priceSymbol,
            string memory nftName,
            string memory nftSymbol
        )
    {
        requireBatchExist(_nft);
        NFT_Batch storage batch = nftBatches[_nft];
        return (
            nftBatches[_nft],
            batch.priceToken.name(),
            batch.priceToken.symbol(),
            batch.nft.name(),
            batch.nft.symbol()
        );
    }

    /// @notice allows to get the price of an nft batch
    function getPrice(DefiMinerNFT _nft) external view returns (uint256) {
        requireBatchExist(_nft);
        NFT_Batch storage batch = nftBatches[_nft];
        return batch.pricePerNFT;
    }

    /// @notice allows to get the price token of an nft batch
    function getPriceToken(DefiMinerNFT _nft) external view returns (ERC20) {
        requireBatchExist(_nft);
        NFT_Batch storage batch = nftBatches[_nft];
        return batch.priceToken;
    }

    function getWhitelist(DefiMinerNFT _nft) external view returns (Whitelist) {
        requireBatchExist(_nft);
        NFT_Batch storage batch = nftBatches[_nft];
        require(
            batch.usesWhitelist,
            "Shop: This NFT Batch doesn't use a whitelist."
        );
        return batch.whitelist;
    }

    // ## Internal functions ##

    /// @dev internal function that creates the batches and saves them to storage. There can only be one batch per NFT.
    function _createNFTBatch(
        DefiMinerNFT _nft,
        ERC20 _priceToken,
        uint256 _pricePerNFT,
        uint256 _maxSellAmount,
        uint256 _alreadySold,
        address _treasuryAddress,
        string memory _description,
        uint256 limitPerCustomer,
        Whitelist _whitelist
    ) internal {
        require(_nft.getShop() == this, "Shop Variable of DefiMinerNFT wrong.");
        require(!nftBatches[_nft].exist, "Shop: NFT Batch already exists.");

        require(
            _maxSellAmount <= _nft.getSaleLimit(),
            "Shop: You can't sell more nfts then the nft sale limit."
        );
        /// @dev Calculates how many nfts are left for the sale.
        require(
            _maxSellAmount <=
                _nft.getSaleLimit() - _nft.totalSupply() + gifted[_nft],
            "Shop: You can't sell more nfts then the nft sale limit."
        );

        nftBatches[_nft] = NFT_Batch(
            block.timestamp,
            _nft,
            _priceToken,
            _pricePerNFT,
            _maxSellAmount,
            _alreadySold,
            _treasuryAddress,
            _description,
            true,
            limitPerCustomer,
            _whitelist,
            address(_whitelist) != address(0)
        );

        /// @dev Triggers the subscriber functions.
        for (uint256 i = 0; i < subscribers.length; i++) {
            ShopSubscriber sub = ShopSubscriber(address(subscribers[i]));
            sub.onBatchCreate(
                _nft,
                _priceToken,
                _pricePerNFT,
                _maxSellAmount,
                _alreadySold,
                _treasuryAddress,
                _description,
                limitPerCustomer,
                _whitelist
            );
        }

        emit NFTBatchCreated(
            _nft,
            _priceToken,
            _pricePerNFT,
            _maxSellAmount,
            _alreadySold,
            _treasuryAddress,
            _description
        );
    }

    function requireBatchExist(DefiMinerNFT _nft) internal view{
        require(_nft.getShop() == this, "Shop: Shop Variable of NFT wrong.");
        require(nftBatches[_nft].exist, "Shop: No Batch found for this NFT.");
    }
}
