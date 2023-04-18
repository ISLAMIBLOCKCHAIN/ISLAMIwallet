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

    function totalSupply() external view returns (uint256);
}

contract iGold is ERC20, Ownable {
    using SafeMath for uint256;

    IPMMContract public pmmContract;
    IiGoldNFT public iGoldNFT;

    address public constant deadWallet =
        0x000000000000000000000000000000000000dEaD;

    address public goldBuyer;    

    IERC20 public iGoldToken;
    IERC20 public islamiToken;
    IERC20 public usdtToken;
    AggregatorV3Interface internal goldPriceFeed;

    mapping(address => bool) public admins;

    modifier onlyAdmin() {
        require(admins[msg.sender], "Caller is not admin");
        _;
    }

    modifier notPausedTrade() {
        require(!isPaused, "Trading is paused");
        _;
    }

    event iGoldNFTMinted(address indexed user, uint256 nftId);
    event iGoldNFTReturned(address indexed user, uint256 indexed nftId);
    event goldReserved(string Type, uint256 goldAddedInGrams, uint256 totalGoldInGrams);
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

    uint256 public constant iGoldTokensPerOunce = 31103476800;
    uint256 public goldReserve; // in grams
    uint256 public usdtVault;
    uint256 public feesBurned;
    uint256 public physicalGoldFee = 50 * 1e6;
    uint256 public physicalGoldFeeSwiss = 200 * 1e6;

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
        iGoldToken = IERC20(address(this));
        pmmContract = IPMMContract(_pmmContract); // 0x14afbB9E6Ab4Ab761f067fA131e46760125301Fc
        goldPriceFeed = AggregatorV3Interface(_goldPriceFeed); //(0x0C466540B2ee1a31b441671eac0ca886e051E410);
        iGoldNFT = IiGoldNFT(_iGoldNFT); //0x6E644B9d53812fdb92bB026Ec9a42B67D2908f26
        admins[msg.sender];
    }

    function addUSDT(uint256 _amount) external{
        require(usdtToken.transferFrom(msg.sender, address(this), _amount), "Check USDT balance or allowance");
        usdtVault += _amount;
    }

    function setNFTContractAddress(address _iGoldNFT) external onlyOwner {
        require(_iGoldNFT != address(0x0), "Zero address");
        iGoldNFT = IiGoldNFT(_iGoldNFT);
    }

    function pause(bool _status) external onlyOwner returns (bool) {
        int256 _goldPrice = getLatestGoldPriceOunce();
        if(_status){
            require(_goldPrice == 0, "gold price is not zero");
        } else{
            require(_goldPrice > 0, "gold price is zero");
        }
        isPaused = _status;
        return (_status);
    }

    function setPhysicalGoldFee(uint256 newFeeLocal, uint256 newFeeSwiss) external onlyOwner {
        physicalGoldFee = newFeeLocal * 1e6;
        physicalGoldFeeSwiss = newFeeSwiss * 1e6;
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
        //(, int256 pricePerOunce, , , ) = goldPriceFeed.latestRoundData();

        int256 pricePerGram = getLatestGoldPriceOunce() * 1e8 / 3110347680; // Multiplied by 10^8 to handle decimals

        return pricePerGram;
    }

    function getIGoldPrice() public view returns (int256) {
        int256 iGoldPrice = (getLatestGoldPriceGram()) / 10;
        return iGoldPrice;
    }

    function addGoldReserve(uint256 amountGold) external onlyAdmin {
        goldReserve += amountGold;
        emit goldReserved("Add", amountGold, goldReserve);
    }

    function removeGoldReserve(uint256 amountGold) external onlyOwner {
        goldReserve -= amountGold;
        emit goldReserved("Remove", amountGold, goldReserve);
    }

    function buy(uint256 _usdtAmount) internal notPausedTrade returns (uint256){
        //uint256 _totalSupply = totalSupply();
        require(
            totalSupply() <= goldReserve.mul(1e8).div(10),
            "gold reserve reached"
        );
        int256 goldPrice = getLatestGoldPriceGram();
        require(goldPrice > 0, "Invalid gold price");

        uint256 _iGoldAmount = _usdtAmount.mul(1e2).mul(1e1).mul(1e8).div(
            uint256(goldPrice)
        ); // 0.1g per token
        uint256 islamiFee = getIslamiPrice(_usdtAmount.div(100)); // 1% fee

        emit trade(
            "Buy",
            _iGoldAmount.div(1e8),
            goldPrice / (1e8),
            _usdtAmount / (1e6),
            islamiFee / (1e7)
        );

        require(
            usdtToken.transferFrom(msg.sender, address(this), _usdtAmount),
            "Check USDT allowance or user balance"
        );
        require(
            islamiToken.transferFrom(msg.sender, deadWallet, islamiFee),
            "Check ISLAMI allowance or user balance"
        );

        usdtVault = usdtVault.add(_usdtAmount);

        feesBurned = feesBurned.add(islamiFee);

        _mint(msg.sender, _iGoldAmount);
        return _iGoldAmount;
    }

    function sell(uint256 _iGoldAmount) public notPausedTrade {
        int256 goldPrice = getLatestGoldPriceGram();
        require(goldPrice > 0, "Invalid gold price");

        uint256 _usdtAmount = _iGoldAmount
            .mul(uint256(goldPrice))
            .div(1e4)
            .div(1e1)
            .div(1e6); // 0.1g per token
        uint256 islamiFee = getIslamiPrice(_usdtAmount.div(100)); // 1% fee

        emit trade("Sell", _iGoldAmount, goldPrice, _usdtAmount, islamiFee);

        _burn(msg.sender, _iGoldAmount);
        require(
            usdtToken.transfer(msg.sender, _usdtAmount),
            "USDT amount in contract does not cover your sell!"
        );
        require(
            islamiToken.transferFrom(msg.sender, deadWallet, islamiFee),
            "Check ISLAMI allowance or user balance"
        );

        usdtVault = usdtVault.sub(_usdtAmount);

        feesBurned = feesBurned.add(islamiFee);
    }

    

    function receivePhysicalGold(
        uint256 ounceId,
        uint256 ounceType,
        string calldata deliveryDetails
    ) external notPausedTrade {
        uint256 feeInUSDT;
        if(ounceType == 0){
            feeInUSDT = physicalGoldFee;
        } else{
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
        goldReserve = goldReserve.sub(iGoldTokensPerOunce);

        usdtToken.transferFrom(msg.sender, address(this), feeInUSDT);
        usdtVault = usdtVault.add(feeInUSDT);

        emit PhysicalGoldRequest(msg.sender, iGoldTokensPerOunce, deliveryDetails);
    }

    function checkReserves()
        public
        view
        returns (uint256 goldValue, uint256 usdtInVault)
    {
        int256 goldPrice = getLatestGoldPriceGram();
        require(goldPrice > 0, "Invalid gold price");
        uint256 iGoldInNFT = iGoldTokensPerOunce * (iGoldNFT.totalSupply());
        uint256 totalMintedGold = totalSupply() + iGoldInNFT; // Total minted iGold tokens (each token represents 0.1g of gold)
        goldValue = totalMintedGold
            .mul(uint256(goldPrice))
            .div(1e4)
            .div(1e1)
            .div(1e6); // Calculate the value of minted iGold tokens in USDT
        usdtInVault = usdtVault; // Current USDT in the contract

        return (goldValue, usdtInVault);
    }

    function mintIGoldNFT() external {
        uint256 iGoldBalance = balanceOf(msg.sender);

        require(
            iGoldBalance >= iGoldTokensPerOunce,
            "iGold balance not sufficient for an iGoldNFT"
        );
        _burn(msg.sender, iGoldTokensPerOunce);
        uint256 nftId = iGoldNFT.mint(msg.sender);

        emit iGoldNFTMinted(msg.sender, nftId);
    }

    function returnIGoldNFT(uint256 nftId) external {
        require(
            iGoldNFT.ownerOf(nftId) == msg.sender,
            "Caller is not the owner of this NFT"
        );

        iGoldNFT.burn(msg.sender, nftId);
        _mint(msg.sender, iGoldTokensPerOunce);

        emit iGoldNFTReturned(msg.sender, nftId);
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
