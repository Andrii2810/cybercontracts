// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.14;

import { BeaconProxy } from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";

import { ISubscribeNFT } from "../interfaces/ISubscribeNFT.sol";
import { IEssenceNFT } from "../interfaces/IEssenceNFT.sol";
import { ISubscribeMiddleware } from "../interfaces/ISubscribeMiddleware.sol";
import { IEssenceMiddleware } from "../interfaces/IEssenceMiddleware.sol";
import { ICyberEngine } from "../interfaces/ICyberEngine.sol";

import { DataTypes } from "./DataTypes.sol";
import { Constants } from "./Constants.sol";
import { LibString } from "./LibString.sol";

library Actions {
    /**
     * @dev Watch ProfileNFT contract for events, see comments in IProfileNFTEvents.sol for the
     * following events
     */
    event DeploySubscribeNFT(
        uint256 indexed profileId,
        address indexed subscribeNFT
    );
    event RegisterEssence(
        uint256 indexed profileId,
        uint256 indexed essenceId,
        string name,
        string symbol,
        string essenceTokenURI,
        address essenceMw,
        bytes prepareReturnData
    );
    event DeployEssenceNFT(
        uint256 indexed profileId,
        uint256 indexed essenceId,
        address indexed essenceNFT
    );
    event CollectEssence(
        address indexed collector,
        uint256 indexed tokenId,
        uint256 indexed profileId,
        bytes preData,
        bytes postData
    );
    event Subscribe(
        address indexed sender,
        uint256[] profileIds,
        bytes[] preDatas,
        bytes[] postDatas
    );

    event SetSubscribeData(
        uint256 indexed profileId,
        string tokenURI,
        address mw,
        bytes prepareReturnData
    );

    event SetEssenceData(
        uint256 indexed profileId,
        uint256 indexed essenceId,
        string tokenURI,
        address mw,
        bytes prepareReturnData
    );

    function subscribe(
        DataTypes.SubscribeData calldata data,
        mapping(uint256 => DataTypes.SubscribeStruct)
            storage _subscribeByProfileId,
        mapping(uint256 => DataTypes.ProfileStruct) storage _profileById
    ) external returns (uint256[] memory result) {
        require(data.profileIds.length > 0, "NO_PROFILE_IDS");
        require(
            data.profileIds.length == data.preDatas.length &&
                data.preDatas.length == data.postDatas.length,
            "LENGTH_MISMATCH"
        );

        result = new uint256[](data.profileIds.length);

        for (uint256 i = 0; i < data.profileIds.length; i++) {
            address subscribeNFT = _subscribeByProfileId[data.profileIds[i]]
                .subscribeNFT;
            address subscribeMw = _subscribeByProfileId[data.profileIds[i]]
                .subscribeMw;
            // lazy deploy subscribe NFT
            if (subscribeNFT == address(0)) {
                subscribeNFT = _deploySubscribeNFT(
                    data.subBeacon,
                    data.profileIds[i],
                    _subscribeByProfileId,
                    _profileById
                );
                emit DeploySubscribeNFT(data.profileIds[i], subscribeNFT);
            }
            if (subscribeMw != address(0)) {
                ISubscribeMiddleware(subscribeMw).preProcess(
                    data.profileIds[i],
                    data.sender,
                    subscribeNFT,
                    data.preDatas[i]
                );
            }
            result[i] = ISubscribeNFT(subscribeNFT).mint(data.sender);
            if (subscribeMw != address(0)) {
                ISubscribeMiddleware(subscribeMw).postProcess(
                    data.profileIds[i],
                    data.sender,
                    subscribeNFT,
                    data.postDatas[i]
                );
            }
        }
        emit Subscribe(
            data.sender,
            data.profileIds,
            data.preDatas,
            data.postDatas
        );
    }

    function collect(
        DataTypes.CollectData calldata data,
        mapping(uint256 => mapping(uint256 => DataTypes.EssenceStruct))
            storage _essenceByIdByProfileId
    ) external returns (uint256 tokenId) {
        require(
            bytes(
                _essenceByIdByProfileId[data.profileId][data.essenceId].tokenURI
            ).length != 0,
            "ESSENCE_NOT_REGISTERED"
        );
        address essenceNFT = _essenceByIdByProfileId[data.profileId][
            data.essenceId
        ].essenceNFT;
        address essenceMw = _essenceByIdByProfileId[data.profileId][
            data.essenceId
        ].essenceMw;

        // lazy deploy essence NFT
        if (essenceNFT == address(0)) {
            bytes memory initData = abi.encodeWithSelector(
                IEssenceNFT.initialize.selector,
                data.profileId,
                data.essenceId,
                _essenceByIdByProfileId[data.profileId][data.essenceId].name,
                _essenceByIdByProfileId[data.profileId][data.essenceId].symbol,
                _essenceByIdByProfileId[data.profileId][data.essenceId]
                    .transferable
            );
            essenceNFT = address(
                new BeaconProxy{ salt: bytes32(data.profileId) }(
                    data.essBeacon,
                    initData
                )
            );
            _essenceByIdByProfileId[data.profileId][data.essenceId]
                .essenceNFT = essenceNFT;
            emit DeployEssenceNFT(data.profileId, data.essenceId, essenceNFT);
        }
        // run middleware before collecting essence
        if (essenceMw != address(0)) {
            IEssenceMiddleware(essenceMw).preProcess(
                data.profileId,
                data.essenceId,
                data.collector,
                essenceNFT,
                data.preData
            );
        }
        tokenId = IEssenceNFT(essenceNFT).mint(data.collector);
        if (essenceMw != address(0)) {
            IEssenceMiddleware(essenceMw).postProcess(
                data.profileId,
                data.essenceId,
                data.collector,
                essenceNFT,
                data.postData
            );
        }
        emit CollectEssence(
            data.collector,
            tokenId,
            data.profileId,
            data.preData,
            data.postData
        );
    }

    function registerEssence(
        DataTypes.RegisterEssenceData calldata data,
        address engine,
        mapping(uint256 => DataTypes.ProfileStruct) storage _profileById,
        mapping(uint256 => mapping(uint256 => DataTypes.EssenceStruct))
            storage _essenceByIdByProfileId
    ) external returns (uint256) {
        require(
            data.essenceMw == address(0) ||
                ICyberEngine(engine).isEssenceMwAllowed(data.essenceMw),
            "ESSENCE_MW_NOT_ALLOWED"
        );

        uint256 id = ++_profileById[data.profileId].essenceCount;
        _essenceByIdByProfileId[data.profileId][id].name = data.name;
        _essenceByIdByProfileId[data.profileId][id].symbol = data.symbol;
        _essenceByIdByProfileId[data.profileId][id].tokenURI = data
            .essenceTokenURI;
        _essenceByIdByProfileId[data.profileId][id].transferable = data
            .transferable;
        bytes memory returnData;
        if (data.essenceMw != address(0)) {
            _essenceByIdByProfileId[data.profileId][id].essenceMw = data
                .essenceMw;
            returnData = IEssenceMiddleware(data.essenceMw).setEssenceMwData(
                data.profileId,
                id,
                data.initData
            );
        }

        emit RegisterEssence(
            data.profileId,
            id,
            data.name,
            data.symbol,
            data.essenceTokenURI,
            data.essenceMw,
            returnData
        );
        return id;
    }

    function setSubscribeData(
        uint256 profileId,
        string calldata uri,
        address mw,
        bytes calldata data,
        address engine,
        mapping(uint256 => DataTypes.SubscribeStruct)
            storage _subscribeByProfileId
    ) external {
        require(
            mw == address(0) || ICyberEngine(engine).isSubscribeMwAllowed(mw),
            "SUB_MW_NOT_ALLOWED"
        );
        _subscribeByProfileId[profileId].subscribeMw = mw;
        bytes memory returnData;
        if (mw != address(0)) {
            returnData = ISubscribeMiddleware(mw).setSubscribeMwData(
                profileId,
                data
            );
        }
        _subscribeByProfileId[profileId].tokenURI = uri;
        emit SetSubscribeData(profileId, uri, mw, returnData);
    }

    function setEssenceData(
        uint256 profileId,
        uint256 essenceId,
        string calldata uri,
        address mw,
        bytes calldata data,
        address engine,
        mapping(uint256 => mapping(uint256 => DataTypes.EssenceStruct))
            storage _essenceByIdByProfileId
    ) external {
        require(
            mw == address(0) || ICyberEngine(engine).isEssenceMwAllowed(mw),
            "ESSENCE_MW_NOT_ALLOWED"
        );
        _essenceByIdByProfileId[profileId][essenceId].essenceMw = mw;
        bytes memory returnData;
        if (mw != address(0)) {
            returnData = IEssenceMiddleware(mw).setEssenceMwData(
                profileId,
                essenceId,
                data
            );
        }
        _essenceByIdByProfileId[profileId][essenceId].tokenURI = uri;
        emit SetEssenceData(profileId, essenceId, uri, mw, returnData);
    }

    function _deploySubscribeNFT(
        address subBeacon,
        uint256 profileId,
        mapping(uint256 => DataTypes.SubscribeStruct)
            storage _subscribeByProfileId,
        mapping(uint256 => DataTypes.ProfileStruct) storage _profileById
    ) private returns (address) {
        string memory name = string(
            abi.encodePacked(
                _profileById[profileId].handle,
                Constants._SUBSCRIBE_NFT_NAME_SUFFIX
            )
        );
        string memory symbol = string(
            abi.encodePacked(
                LibString.toUpper(_profileById[profileId].handle),
                Constants._SUBSCRIBE_NFT_SYMBOL_SUFFIX
            )
        );
        address subscribeNFT = address(
            new BeaconProxy{ salt: bytes32(profileId) }(
                subBeacon,
                abi.encodeWithSelector(
                    ISubscribeNFT.initialize.selector,
                    profileId,
                    name,
                    symbol
                )
            )
        );

        _subscribeByProfileId[profileId].subscribeNFT = subscribeNFT;
        return subscribeNFT;
    }
}
