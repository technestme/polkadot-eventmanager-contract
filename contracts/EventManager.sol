// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UniqueV2TokenMinter, Attribute, CrossAddress} from "unique-contracts/UniqueV2TokenMinter.sol";
import {UniqueV2CollectionMinter} from "unique-contracts/UniqueV2CollectionMinter.sol";
import {Property, CollectionMode, TokenPropertyPermission, CollectionLimitValue, CollectionLimitField, CollectionNestingAndPermission} from "@unique-nft/solidity-interfaces/contracts/CollectionHelpers.sol";
import {UniqueNFT} from "@unique-nft/solidity-interfaces/contracts/UniqueNFT.sol";

struct EventConfig {
    uint256 startTimestamp;
    uint256 endTimestamp;
    string collectionCoverImage;
    string tokenImage;
    Attribute[] attributes;
    CrossAddress owner;
}

contract EventManager is UniqueV2CollectionMinter, UniqueV2TokenMinter {
    /// @notice Only one NFT per account can be minted.
    uint256 public constant ACCOUNT_TOKEN_LIMIT = 1;

    // TODO: do we need this fee? Should we support withdraw?
    uint256 private s_collectionCreationFee;
    mapping(address collection => EventConfig) private s_eventConfigOf;

    event EventCreated(uint256 collectionId, address collectionAddress);
    event TokenClaimed(CrossAddress indexed owner, uint256 indexed colletionId, uint256 tokenId);

    error InvalidCreationFee();
    error EventNotStarted();
    error EventFinished();

    ///@dev all token properties will be mutable for collection admin
    constructor(uint256 _collectionCreationFee) payable UniqueV2CollectionMinter(true, false, true) {
        s_collectionCreationFee = _collectionCreationFee;
    }

    function createCollection(
        string memory _name,
        string memory _description,
        string memory _symbol,
        bool _soulbound,
        EventConfig memory _eventConfig
    ) external payable {
        if (msg.value != s_collectionCreationFee) revert InvalidCreationFee();

        // Set collection limits
        CollectionLimitValue[] memory collectionLimits = new CollectionLimitValue[](2);
        // Every account can own only 1 NFT (ACCOUNT_TOKEN_LIMIT)
        collectionLimits[0] = CollectionLimitValue({
            field: CollectionLimitField.AccountTokenOwnership,
            value: ACCOUNT_TOKEN_LIMIT
        });

        // if soulbound transfers are not allowed
        if (_soulbound)
            collectionLimits[1] = CollectionLimitValue({field: CollectionLimitField.TransferEnabled, value: 0});

        address collectionAddress = _createCollection(
            _name,
            _description,
            _symbol,
            _eventConfig.collectionCoverImage,
            CollectionNestingAndPermission({token_owner: false, collection_admin: false, restricted: new address[](0)}),
            collectionLimits,
            new Property[](0),
            new TokenPropertyPermission[](0)
        );

        UniqueNFT collection = UniqueNFT(collectionAddress);

        // Set collection sponsorship
        // Every transaction will be paid by the EventManager
        collection.setCollectionSponsorCross(CrossAddress({eth: address(this), sub: 0}));
        collection.confirmCollectionSponsorship();

        // Save collection event
        EventConfig storage eventConfig = s_eventConfigOf[collectionAddress];

        eventConfig.startTimestamp = _eventConfig.startTimestamp;
        eventConfig.endTimestamp = _eventConfig.endTimestamp;
        eventConfig.tokenImage = _eventConfig.tokenImage;

        for (uint i = 0; i < _eventConfig.attributes.length; i++) {
            eventConfig.attributes.push(_eventConfig.attributes[i]);
        }

        emit EventCreated(COLLECTION_HELPERS.collectionId(collectionAddress), collectionAddress);
    }

    function createToken(address _collectionAddress, CrossAddress memory _owner) external {
        EventConfig memory collectionEvent = s_eventConfigOf[_collectionAddress];

        // 1. Check if the event has started and not finished yet
        if (block.timestamp < collectionEvent.startTimestamp) revert EventNotStarted();
        if (block.timestamp > collectionEvent.endTimestamp) revert EventFinished();

        // 2. Create NFT
        uint256 tokenId = _createToken(
            _collectionAddress,
            collectionEvent.tokenImage,
            collectionEvent.attributes,
            _owner
        );

        emit TokenClaimed(_owner, COLLECTION_HELPERS.collectionId(_collectionAddress), tokenId);
    }

    function getCollectionCreationFee() external view returns (uint256) {
        return s_collectionCreationFee;
    }

    function getEventConfig(address _collectionAddress) external view returns (EventConfig memory) {
        return s_eventConfigOf[_collectionAddress];
    }
}
