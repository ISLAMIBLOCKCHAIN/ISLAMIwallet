// SPDX-License-Identifier: MIT

// ISLAMI Gold iGold Liquidity Template

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IiGold {
    function getLatestGoldPriceGram() external view returns (int256);

    function getIslamiPrice(uint256) external view returns (uint256);

    function mintLiquidity(address, uint256) external returns (uint256);

    function burnLiquidity(address , uint256 ) external returns(uint256);

    function addMiner(address) external;

    function addGoldReserve(uint256) external;

    function removeGoldReserve(uint256) external;

    function getIGoldPrice() external view returns (int256);

    function totalSupply() external view returns (uint256);

    function addFeesBurned(uint256) external;
}

interface IiGoldNFT {
    function mint(address) external returns (uint256);

    function burn(address, uint256) external;

    function ownerOf(uint256) external returns (address);

    function totalSupply() external view returns (uint256);

    function addMinter(address) external;

    function tag(uint256) external returns(address);
}

interface IdexFactory {
    function getMinerFee(address) external view returns (uint256);
}

pragma solidity 0.8.19;

contract iGoldLiquidity {
    using SafeMath for uint256;

    IiGoldNFT public iGoldNFT;
    IiGold public iGold;
    IdexFactory public factory;

    address public constant deadWallet =
        0x000000000000000000000000000000000000dEaD;

    uint256 public constant iGoldTokensPerOunce = 31103476800;
    uint256 public constant duration = 365 days;

    IERC20 public iGoldToken;
    IERC20 public islamiToken;
    IERC20 public usdtToken;

    address public investor;
    uint256 public id;
    string public name;
    string public companyAddress;
    string public latitude;
    string public longitude;
    uint256 public safeReserve; // Minted iGold

    uint256 public usdtVault;
    uint256 public iGoldVault;
    uint256 public feesCollected;
    uint256 public iGoldSafeforNFT;

    uint256 public physicalGoldFee = 50 * 1e6;
    uint256 public physicalGoldFeeSwiss = 200 * 1e6;

    mapping(address => uint256) public liquidityPower;
    mapping(address => uint256) public balanceFromThis;

    event trade(
        string Type,
        uint256 iGold,
        int256 priceInUSD,
        uint256 amountPay,
        uint256 feesInISLAMI
    );
    event iGoldNFTMinted(address indexed user, uint256 nftId);
    event iGoldNFTReturned(address indexed user, uint256 indexed nftId);
    event PhysicalGoldRequest(
        address indexed user,
        uint256 goldAmount,
        string deliveryDetails
    );
    event TokensWithdrawn(
        address indexed token,
        address indexed owner,
        uint256 amount
    );

    constructor(
        address _investor,
        uint256 _id,
        string memory _name,
        string memory _address,
        string memory _la,
        string memory _li,
        uint256 _mintedGold,
        IERC20 _iGoldToken,
        IERC20 _usdtToken,
        IERC20 _islamiToken
    ) {
        require(_investor != address(0x0), "address zero!");
        investor = _investor;
        id = _id;
        name = _name;
        companyAddress = _address;
        latitude = _la;
        longitude = _li;
        safeReserve = _mintedGold;
        iGoldVault = _mintedGold.mul(1e1);
        iGoldToken = _iGoldToken;
        usdtToken = _usdtToken;
        islamiToken = _islamiToken;
        iGold = IiGold(address(_iGoldToken));
        factory = IdexFactory(address(msg.sender));
    }

    function setPhysicalGoldFee(uint256 newFeeLocal, uint256 newFeeSwiss)
        external
    {
        require(msg.sender == investor, "sender not owner");
        physicalGoldFee = newFeeLocal * 1e6;
        physicalGoldFeeSwiss = newFeeSwiss * 1e6;
    }

    function getFeeRate() public view returns (uint256) {
        uint256 _feeRate = factory.getMinerFee(investor);
        return _feeRate;
    }

    function buy(uint256 _usdtAmount) external returns (uint256) {
        int256 goldPrice = iGold.getLatestGoldPriceGram();
        require(goldPrice > 0, "Invalid gold price");

        uint256 _iGoldAmount = _usdtAmount.mul(1e2).mul(1e1).mul(1e8).div(
            uint256(goldPrice)
        ); // 0.1g per token
        require(
            _iGoldAmount <= iGoldVault,
            "Gold amount exceed contract balance"
        );
        uint256 islamiFee = iGold.getIslamiPrice(_usdtAmount.div(100)); // 1% fee
        uint256 islamiFeeMiner = 0;
        if (getFeeRate() > 0) {
            islamiFeeMiner = islamiFee.mul(getFeeRate()).div(100); // % of the 1% fee

            require(
                islamiToken.transferFrom(
                    msg.sender,
                    deadWallet,
                    islamiFee.sub(islamiFeeMiner)
                ),
                "Check ISLAMI allowance or user balance"
            );
            require(
                islamiToken.transferFrom(msg.sender, investor, islamiFeeMiner),
                "Check ISLAMI allowance or user balance"
            );
        } else {
            require(
                islamiToken.transferFrom(
                    msg.sender,
                    deadWallet,
                    islamiFee
                ),
                "Check ISLAMI allowance or user balance"
            );
        }

        emit trade("Buy", _iGoldAmount, goldPrice, _usdtAmount, islamiFee);

        require(
            usdtToken.transferFrom(msg.sender, address(this), _usdtAmount),
            "Check USDT allowance or user balance"
        );

        feesCollected = feesCollected.add(islamiFeeMiner);
        usdtVault = usdtVault.add(_usdtAmount);

        iGold.addFeesBurned(islamiFee);

        iGoldToken.transfer(msg.sender, _iGoldAmount);
        balanceFromThis[msg.sender] = balanceFromThis[msg.sender].add(_iGoldAmount);
        iGoldVault = iGoldVault.sub(_iGoldAmount);
        return _iGoldAmount;
    }

    function sell(uint256 _iGoldAmount) public {
        require(balanceFromThis[msg.sender] >= _iGoldAmount, "You can only sell what you bought from this contract");
        int256 goldPrice = iGold.getLatestGoldPriceGram();
        require(goldPrice > 0, "Invalid gold price");
        uint256 islamiFeeMiner = 0;
        uint256 _usdtAmount = _iGoldAmount
            .mul(uint256(goldPrice))
            .div(1e4)
            .div(1e1)
            .div(1e6); // 0.1g per token
        uint256 islamiFee = iGold.getIslamiPrice(_usdtAmount.div(100)); // 1% fee

        emit trade("Sell", _iGoldAmount, goldPrice, _usdtAmount, islamiFee);

        require(iGoldToken.transferFrom(msg.sender, address(this), _iGoldAmount),"Check allowance or balance");
        iGoldVault = iGoldVault.add(_iGoldAmount);
        require(
            usdtToken.transfer(msg.sender, _usdtAmount),
            "USDT amount in contract does not cover your sell!"
        );
        usdtVault = usdtVault.sub(_usdtAmount);

        if (getFeeRate() > 0) {
            islamiFeeMiner = islamiFee.mul(getFeeRate()).div(100); // % of the 1% fee

            require(
            islamiToken.transferFrom(msg.sender, deadWallet, islamiFee.sub(islamiFeeMiner)),
            "Check ISLAMI allowance or user balance"
        );

            require(
            islamiToken.transferFrom(msg.sender, investor, islamiFeeMiner),
            "Check ISLAMI allowance or user balance"
        );

        } else{
            require(
            islamiToken.transferFrom(msg.sender, deadWallet, islamiFee),
            "Check ISLAMI allowance or user balance"
        );
        }
        balanceFromThis[msg.sender] = balanceFromThis[msg.sender].sub(_iGoldAmount);
        iGold.addFeesBurned(islamiFee);
    }

    function mintIGoldNFT() external {
        uint256 iGoldBalance = balanceFromThis[msg.sender];

        require(
            iGoldBalance >= iGoldTokensPerOunce,
            "iGold balance not sufficient for an iGoldNFT"
        );
        require(iGoldToken.transferFrom(msg.sender, address(this), iGoldTokensPerOunce),"Check balance or allowance");
        iGoldSafeforNFT = iGoldSafeforNFT.add(iGoldTokensPerOunce);
        uint256 nftId = iGoldNFT.mint(msg.sender);
        balanceFromThis[msg.sender] = balanceFromThis[msg.sender].sub(iGoldTokensPerOunce);

        emit iGoldNFTMinted(msg.sender, nftId);
    }

    function returnIGoldNFT(uint256 nftId) external {
        require(
            iGoldNFT.ownerOf(nftId) == msg.sender,
            "Caller is not the owner of this NFT"
        );
        address _tag = iGoldNFT.tag(nftId);
        require(_tag == address(this), "contract is not the minter of this NFT");
        iGoldNFT.burn(msg.sender, nftId);
        iGoldToken.transfer(msg.sender, iGoldTokensPerOunce);
        iGoldSafeforNFT = iGoldSafeforNFT.sub(iGoldTokensPerOunce);
        balanceFromThis[msg.sender] = balanceFromThis[msg.sender].add(iGoldTokensPerOunce);

        emit iGoldNFTReturned(msg.sender, nftId);
    }

    function receivePhysicalGold(
        uint256 ounceId,
        uint256 ounceType,
        string calldata deliveryDetails
    ) external {
        uint256 feeInUSDT;
        if (ounceType == 0) {
            feeInUSDT = physicalGoldFee;
        } else {
            feeInUSDT = physicalGoldFeeSwiss;
        }

        require(
            usdtToken.balanceOf(msg.sender) >= feeInUSDT,
            "Insufficient USDT balance"
        );
        require(
            usdtToken.allowance(msg.sender, address(this)) >= feeInUSDT,
            "Insufficient USDT allowance"
        );

        iGoldNFT.burn(msg.sender, ounceId);
        // goldReserve = goldReserve.sub(iGoldTokensPerOunce);

        usdtToken.transferFrom(msg.sender, address(this), feeInUSDT);
        usdtVault = usdtVault.add(feeInUSDT);

        emit PhysicalGoldRequest(
            msg.sender,
            iGoldTokensPerOunce,
            deliveryDetails
        );
    }

    function addUSDT(uint256 _amount) external {
        require(
            usdtToken.transferFrom(msg.sender, address(this), _amount),
            "Check USDT balance or allowance"
        );
        usdtVault += _amount;
    }

    function removeiGoldLiquidity(uint256 _amount)external {
        require(msg.sender == investor, "caller is not owner");
        uint256 availableAmount = iGoldToken.balanceOf(address(this)).sub(iGoldSafeforNFT);
        require(_amount <= availableAmount, "Check amount");
        iGold.burnLiquidity(address(this), _amount);
        uint256 amountInGrams = _amount.div(1e1).div(1e8);
        safeReserve = safeReserve.sub(amountInGrams);
        iGold.removeGoldReserve(amountInGrams);
    }
}

                /*********************************************************
                    Proudly Developed by MetaIdentity ltd. Copyright 2023
                **********************************************************/
