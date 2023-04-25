// SPDX-License-Identifier: MIT

// ISLAMI Gold iGold Dex Factory

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./iGoldLiquidityTemplate.sol";


contract iGoldDexFactory is Ownable {
    using SafeMath for uint256;

    uint256 public idCounts;

    IiGold public iGold;
    IiGoldNFT public iGoldNFT;

    address public constant deadWallet =
        0x000000000000000000000000000000000000dEaD;

    IERC20 public iGoldToken;
    IERC20 public islamiToken;
    IERC20 public usdtToken;

    struct goldMiner {
        address investor;
        uint256 id;
        string name;
        string companyAddress;
        string latitude;
        string longitude;
        uint256 safeReserve; // Minted iGold
        uint256 feeRate;
    }

    struct allowedMiner {
        uint256 id;
        string name;
        string companyAddress;
        string latitude;
        string longitude;
        uint256 openReserve; // Available Gold in grams to be minted as iGold
        uint256 safeReserve; // Minted iGold
        uint256 feeRate;
        bool liquidityContract; // check if miner created a liquidity contract
    }

    mapping(address => bool) public miners;
    mapping(address => goldMiner) public liquidityContract;
    mapping(address => allowedMiner) public goldInvestor;

    address[] private _liquidityContracts;

    modifier onlyMiner() {
        require(miners[msg.sender], "Caller is not miner");
        _;
    }

    constructor(
        IERC20 _iGoldToken,
        IERC20 _usdtToken,
        IERC20 _islamiTokne
    ) {
        iGoldToken = _iGoldToken;
        usdtToken = _usdtToken;
        islamiToken = _islamiTokne;
        iGold = IiGold(address(_iGoldToken));
    }

    function getMinerFee(address _investor) public view returns(uint256){
        return goldInvestor[_investor].feeRate;
    }

    function allowMiner(
        address _investor,
        string memory _name,
        string memory _address,
        string memory _la,
        string memory _lo,
        uint256 _goldInGrams,
        uint256 _feeRate
    ) external onlyOwner {
        require(_investor != address(0x0), "address zero!");
        uint256 _id = idCounts;
        goldInvestor[_investor].id = _id;
        goldInvestor[_investor].name = _name;
        goldInvestor[_investor].companyAddress = _address;
        goldInvestor[_investor].latitude = _la;
        goldInvestor[_investor].longitude = _lo;
        goldInvestor[_investor].openReserve = _goldInGrams;
        goldInvestor[_investor].feeRate = _feeRate;
        miners[_investor] = true;
        idCounts++;
    }

    function acceptMining() external onlyMiner {
        require(!goldInvestor[msg.sender].liquidityContract, "Contract was created");
        uint256 minerReserve = goldInvestor[msg.sender].openReserve;
        int256 goldPrice = iGold.getLatestGoldPriceGram();
        require(goldPrice > 0, "Invalid gold price");
        
        uint256 _usdtAmount = uint256(goldPrice).mul(minerReserve).div(1e2);
        uint256 _iGoldAmount = _usdtAmount.mul(1e2).mul(1e1).mul(1e8).div(
            uint256(goldPrice)
        ); // 0.1g per token
        
        uint256 islamiFee = iGold.getIslamiPrice(_usdtAmount.div(100)); // 1% fee

        uint256 goldToMint = _iGoldAmount.div(1e1).div(1e8);
        goldInvestor[msg.sender].openReserve -= goldToMint;
        goldInvestor[msg.sender].safeReserve = goldToMint;

        require(
            islamiToken.allowance(msg.sender, address(this)) >= islamiFee,
            "Check ISLAMI allowance"
        );
        require(
            islamiToken.transferFrom(msg.sender, deadWallet, islamiFee),
            "Check ISLAMI balance"
        );

        iGold.addFeesBurned(islamiFee);

        iGold.addGoldReserve(goldToMint);

        address _liquidityContract = deployiGoldLiquidity(
            msg.sender,
            goldInvestor[msg.sender].id,
            goldInvestor[msg.sender].name,
            goldInvestor[msg.sender].companyAddress,
            goldInvestor[msg.sender].latitude,
            goldInvestor[msg.sender].longitude,
            goldToMint,
            goldInvestor[msg.sender].feeRate
        );
        iGold.mintLiquidity(_liquidityContract, _iGoldAmount);
        goldInvestor[msg.sender].liquidityContract = true;
    }

    function addMiner(
        address _contract,
        address _investor,
        uint256 _id,
        string memory _name,
        string memory _address,
        string memory _la,
        string memory _lo,
        uint256 _mintedGold,
        uint256 _feeRate
    ) private {
        require(_contract != address(0x0), "Liquidity contract address zero!");
        liquidityContract[_contract].investor = _investor;
        liquidityContract[_contract].id = _id;
        liquidityContract[_contract].name = _name;
        liquidityContract[_contract].companyAddress = _address;
        liquidityContract[_contract].latitude = _la;
        liquidityContract[_contract].longitude = _lo;
        liquidityContract[_contract].safeReserve = _mintedGold;
        liquidityContract[_contract].feeRate = _feeRate;
    }

    function deployiGoldLiquidity(
        address _investor,
        uint256 _id,
        string memory _name,
        string memory _address,
        string memory _la,
        string memory _lo,
        uint256 _mintedGold,
        uint256 _feeRate
    ) private returns (address) {
        require(_investor != address(0x0), "address zero!");
        iGoldLiquidity liquidityContractInstance = new iGoldLiquidity(
            _investor,
            _id,
            _name,
            _address,
            _la,
            _lo,
            _mintedGold,
            iGoldToken,
            usdtToken,
            islamiToken
        );
        addMiner(
            address(liquidityContractInstance),
            _investor,
            _id,
            _name,
            _address,
            _la,
            _lo,
            _mintedGold,
            _feeRate
        );
        iGoldNFT.addMinter(address(liquidityContractInstance));
        iGold.addMiner(address(liquidityContractInstance));
        _liquidityContracts.push(address(liquidityContractInstance));
        return address(liquidityContractInstance);
    }

    function getAllLiquidityContracts() external view returns (goldMiner[] memory) {
        goldMiner[] memory goldMinerList = new goldMiner[](_liquidityContracts.length);

        for (uint256 i = 0; i < _liquidityContracts.length; i++) {
            goldMinerList[i] = liquidityContract[_liquidityContracts[i]];
        }

        return goldMinerList;
    }
}

                /*********************************************************
                    Proudly Developed by MetaIdentity ltd. Copyright 2023
                **********************************************************/
