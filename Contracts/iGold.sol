// SPDX-License-Identifier: MIT

// ISLAMI Gold iGold

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface IPMMContract {
    enum RState {
        ONE,
        ABOVE_ONE,
        BELOW_ONE
    }

    function querySellQuote(address trader, uint256 payQuoteAmount)
        external
        view
        returns (
            uint256 receiveBaseAmount,
            uint256 mtFee,
            RState newRState,
            uint256 newQuoteTarget
        );
}

interface IiGoldNFT {
    function mint(address) external returns (uint256);

    function burn(address, uint256) external;

    function ownerOf(uint256) external returns (address);
}

contract iGold is ERC20, Ownable {
    using SafeMath for uint256;

    IPMMContract public pmmContract;
    IiGoldNFT public iGoldNFT;

    address public constant deadWallet =
        0x000000000000000000000000000000000000dEaD;

    IERC20 public islamiToken;
    IERC20 public usdtToken;
    AggregatorV3Interface internal goldPriceFeed;

    mapping(address => bool) public vipMembers;

    modifier onlyVIP() {
        require(vipMembers[msg.sender], "Caller is not a VIP member");
        _;
    }

    modifier notPausedTrade() {
        require(!isPaused, "Contract is paused");
        _;
    }

    event iGoldNFTMinted(address indexed user, uint256 nftId);
    event iGoldNFTReturned(address indexed user, uint256 indexed nftId);
    event goldReserved(string Type, uint256 goldInGrams);
    event trade(
        string Type,
        uint256 iGold,
        int256 priceInUSD,
        uint256 amountPay,
        uint256 feesInISLAMI
    );
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

    uint256 public goldReserve; // in grams
    uint256 public usdtVault;
    uint256 public feesBurned;
    uint256 public physicalGoldFee;

    bool isPaused;

    function decimals() public view virtual override returns (uint8) {
        return 8; //same decimals as price of gold returned from ChainLink
    }

    constructor(
        address _islamiToken,
        address _usdtToken,
        address _pmmContract,
        address _goldPriceFeed,
        address _iGoldNFT
    ) ERC20("iGold", "iGold") {
        islamiToken = IERC20(_islamiToken);
        usdtToken = IERC20(_usdtToken);
        pmmContract = IPMMContract(_pmmContract); // 0x14afbB9E6Ab4Ab761f067fA131e46760125301Fc
        goldPriceFeed = AggregatorV3Interface(_goldPriceFeed); //(0x0C466540B2ee1a31b441671eac0ca886e051E410);
        iGoldNFT = IiGoldNFT(_iGoldNFT); //0x6E644B9d53812fdb92bB026Ec9a42B67D2908f26
        vipMembers[msg.sender] = true;
    }

    function addUSDT(uint256 _amount) external{
        require(usdtToken.transferFrom(msg.sender, address(this), _amount), "Check USDT balance or allowance");
        usdtVault += _amount;
    }

    function setNFTContractAddress(address _iGoldNFT) external onlyOwner {
        require(_iGoldNFT != address(0x0), "Zero address");
        iGoldNFT = IiGoldNFT(_iGoldNFT);
    }

    function addVIPMember(address _member) external onlyOwner {
        require(_member != address(0), "Zero address not allowed");
        require(!vipMembers[_member], "Address is already a VIP member");

        vipMembers[_member] = true;
    }

    function removeVIPMember(address _member) external onlyOwner {
        require(_member != address(0), "Zero address not allowed");
        require(vipMembers[_member], "Address is not a VIP member");

        vipMembers[_member] = false;
    }

    function pause(bool _status) public onlyOwner returns (bool) {
        isPaused = _status;
        return (_status);
    }

    function setPhysicalGoldFee(uint256 newFee) external onlyOwner {
        physicalGoldFee = newFee;
    }

    function setUSDTAddress(address _USDT) external onlyOwner {
        require(_USDT != address(0x0), "Zero address");
        usdtToken = IERC20(_USDT);
    }

    function setISLAMIAddress(address _ISLAMI) external onlyOwner {
        require(_ISLAMI != address(0x0), "Zero address");
        islamiToken = IERC20(_ISLAMI);
    }

    function setIslamiPriceAddress(address _pmmContract) external onlyOwner {
        require(_pmmContract != address(0x0), "Zero address");
        pmmContract = IPMMContract(_pmmContract);
    }

    function setGoldPriceAddress(address _goldPriceFeed) external onlyOwner {
        require(_goldPriceFeed != address(0x0), "Zero address");
        goldPriceFeed = AggregatorV3Interface(_goldPriceFeed);
    }

    function getIslamiPrice(uint256 payQuoteAmount)
        public
        view
        returns (uint256 _price)
    {
        address trader = address(this);
        // Call the querySellQuote function from the PMMContract
        (uint256 receiveBaseAmount, , , ) = pmmContract.querySellQuote(
            trader,
            payQuoteAmount
        );
        _price = receiveBaseAmount;
        return _price;
    }

    function getLatestGoldPriceOunce() public view returns (int256) {
        (, int256 pricePerOunce, , , ) = goldPriceFeed.latestRoundData();
        return pricePerOunce;
    }

    function getLatestGoldPriceGram() public view returns (int256) {
        (, int256 pricePerOunce, , , ) = goldPriceFeed.latestRoundData();

        int256 pricePerGram = pricePerOunce * 1e8 / 3110347680; // Multiplied by 10^8 to handle decimals

        return pricePerGram;
    }

    function addGoldReserve(uint256 amountGold) external onlyOwner {
        goldReserve += amountGold;
        emit goldReserved("Add", amountGold);
    }

    function removeGoldReserve(uint256 amountGold) external onlyOwner {
        goldReserve -= amountGold;
        emit goldReserved("Remove", amountGold);
    }

    function buy(uint256 usdtAmount) public notPausedTrade {
        uint256 _totalSupply = totalSupply();
        require(
            _totalSupply <= goldReserve.mul(1e8).div(10),
            "gold reserve reached"
        );
        int256 goldPrice = getLatestGoldPriceGram();
        require(goldPrice > 0, "Invalid gold price");

        uint256 goldAmount = usdtAmount.mul(1e2).mul(1e1).mul(1e8).div(
            uint256(goldPrice)
        ); // 0.1g per token
        uint256 islamiFee = getIslamiPrice(usdtAmount.div(100)); // 1% fee

        emit trade(
            "Buy",
            goldAmount.div(1e8),
            goldPrice / (1e8),
            usdtAmount / (1e6),
            islamiFee / (1e7)
        );

        require(
            usdtToken.transferFrom(msg.sender, address(this), usdtAmount),
            "Check USDT allowance or user balance"
        );
        require(
            islamiToken.transferFrom(msg.sender, deadWallet, islamiFee),
            "Check ISLAMI allowance or user balance"
        );

        usdtVault = usdtVault.add(usdtAmount);

        feesBurned = feesBurned.add(islamiFee);

        _mint(msg.sender, goldAmount);
    }

    function sell(uint256 goldAmount) public notPausedTrade {
        int256 goldPrice = getLatestGoldPriceGram();
        require(goldPrice > 0, "Invalid gold price");

        uint256 usdtAmount = goldAmount
            .mul(uint256(goldPrice))
            .div(1e4)
            .div(1e1)
            .div(1e6); // 0.1g per token
        uint256 islamiFee = getIslamiPrice(usdtAmount.div(100)); // 1% fee

        emit trade("Sell", goldAmount, goldPrice, usdtAmount, islamiFee);

        _burn(msg.sender, goldAmount);
        require(
            usdtToken.transfer(msg.sender, usdtAmount),
            "USDT amount in contract does not cover your sell!"
        );
        require(
            islamiToken.transferFrom(msg.sender, deadWallet, islamiFee),
            "Check ISLAMI allowance or user balance"
        );

        usdtVault = usdtVault.sub(usdtAmount);

        feesBurned = feesBurned.add(islamiFee);
    }

    function specialBuy(uint256 usdtAmount, uint256 goldReserveAmount)
        external
        onlyVIP
        notPausedTrade
    {
        goldReserve = goldReserve.add(goldReserveAmount);
        buy(usdtAmount);
        emit goldReserved("Add", goldReserveAmount);
    }

    function receivePhysicalGold(
        uint256 goldAmount,
        string calldata deliveryDetails
    ) external onlyVIP notPausedTrade {
        int256 goldPrice = getLatestGoldPriceGram();
        require(goldPrice > 0, "Invalid gold price");

        uint256 feeInUSDT = physicalGoldFee;

        require(goldReserve >= goldAmount, "Not enough gold in reserve");
        require(usdtVault >= feeInUSDT, "Not enough USDT in vault");
        require(
            usdtToken.balanceOf(msg.sender) >= feeInUSDT,
            "Insufficient USDT balance"
        );
        require(
            usdtToken.allowance(msg.sender, address(this)) >= feeInUSDT,
            "Insufficient USDT allowance"
        );

        _burn(msg.sender, goldAmount);
        goldReserve = goldReserve.sub(goldAmount);

        usdtToken.transferFrom(msg.sender, address(this), feeInUSDT);
        usdtVault = usdtVault.add(feeInUSDT);

        emit PhysicalGoldRequest(msg.sender, goldAmount, deliveryDetails);
    }

    function checkReserves()
        public
        view
        returns (uint256 goldValue, uint256 usdtInVault)
    {
        int256 goldPrice = getLatestGoldPriceGram();
        require(goldPrice > 0, "Invalid gold price");

        uint256 totalMintedGold = totalSupply(); // Total minted iGold tokens (each token represents 0.1g of gold)
        goldValue = totalMintedGold
            .mul(uint256(goldPrice))
            .div(1e4)
            .div(1e1)
            .div(1e6); // Calculate the value of minted iGold tokens in USDT
        usdtInVault = usdtVault; // Current USDT in the contract

        return (goldValue, usdtInVault);
    }

    function mintiGoldNFT() external {
        uint256 iGoldBalance = balanceOf(msg.sender);
        uint256 iGoldOunce = iGoldTokensPerOunce();

        require(
            iGoldBalance >= iGoldOunce,
            "iGold balance not sufficient for an iGoldNFT"
        );
        _burn(msg.sender, iGoldOunce);
        uint256 nftId = iGoldNFT.mint(msg.sender);

        emit iGoldNFTMinted(msg.sender, nftId);
    }

    function returniGoldNFT(uint256 nftId) external {
        require(
            iGoldNFT.ownerOf(nftId) == msg.sender,
            "Caller is not the owner of this NFT"
        );

        uint256 iGoldOunce = iGoldTokensPerOunce();

        iGoldNFT.burn(msg.sender, nftId);
        _mint(msg.sender, iGoldOunce);

        emit iGoldNFTReturned(msg.sender, nftId);
    }

    function iGoldTokensPerOunce() public pure returns (uint256) {
        return 31103476800;
    }

    function withdrawTokens(address tokenAddress, uint256 amount)
        external
        onlyOwner
    {
        require(
            tokenAddress == address(0x0)
                ? address(this).balance >= amount
                : IERC20(tokenAddress).balanceOf(address(this)) >= amount,
            "Insufficient balance"
        );

        if (tokenAddress == address(usdtToken)) {
            (uint256 _goldValue, ) = checkReserves();
            uint256 difference = usdtVault.sub(_goldValue);
            require(amount <= difference, "No extra USDT in contract");
            usdtVault -= amount;

            IERC20(usdtToken).transfer(msg.sender, amount);
        } else if (tokenAddress == address(0x0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20 token = IERC20(tokenAddress);
            token.transfer(msg.sender, amount);
        }

        emit TokensWithdrawn(tokenAddress, msg.sender, amount);
    }
}

                /*********************************************************
                    Proudly Developed by MetaIdentity ltd. Copyright 2023
                **********************************************************/
