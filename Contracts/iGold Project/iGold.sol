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

    IERC20 public iGoldToken;
    IERC20 public islamiToken;
    IERC20 public usdtToken;
    AggregatorV3Interface public goldPriceFeed;

    mapping(address => bool) public admins;
    mapping(address => bool) public miners;

    modifier onlyAdmin() {
        require(admins[msg.sender], "Caller is not admin");
        _;
    }

    modifier onlyMiner() {
        require(miners[msg.sender], "Caller is not miner");
        _;
    }

    modifier notPausedTrade() {
        require(!isPaused, "Trading is paused");
        _;
    }

    event iGoldNFTMinted(address indexed user, uint256 nftId);
    event iGoldNFTReturned(address indexed user, uint256 indexed nftId);
    event goldReserved(
        string Type,
        uint256 goldAddedInGrams,
        uint256 totalGoldInGrams
    );
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

    bool public isPaused;

    address[] public liquidityContracts;

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
        islamiToken = IERC20(_islamiToken);  // 0x9c891326Fd8b1a713974f73bb604677E1E63396D
        usdtToken = IERC20(_usdtToken);  // 0xc2132D05D31c914a87C6611C10748AEb04B58e8F
        iGoldToken = IERC20(address(this));
        pmmContract = IPMMContract(_pmmContract); // 0x14afbB9E6Ab4Ab761f067fA131e46760125301Fc
        goldPriceFeed = AggregatorV3Interface(_goldPriceFeed); //(0x0C466540B2ee1a31b441671eac0ca886e051E410);
        iGoldNFT = IiGoldNFT(_iGoldNFT); //0xB6aD219F3b0951AFF903bc763210599d852205Bd
        admins[msg.sender] = true;
    }

    function addAdmin(address _admin) external onlyOwner{
        require(_admin != address(0x0), "zero address");
        admins[_admin] = true;
    }

    function removeAdmin(address _admin) external onlyOwner{
        require(_admin != address(0x0), "zero address");
        admins[_admin] = false;
    }

    function addFeesBurned(uint256 _amount) external onlyAdmin{
        feesBurned += _amount;
    }

    function addMiner(address _miner) external onlyAdmin{
        require(_miner != address(0x0), "zero address!");
        miners[_miner] = true;
        liquidityContracts.push(_miner);
    }

    function getAllLiquidityContracts() external view returns (address[] memory) {
        return liquidityContracts;
    }

    function setNFTContractAddress(address _iGoldNFT) external onlyOwner {
        require(_iGoldNFT != address(0x0), "Zero address");
        iGoldNFT = IiGoldNFT(_iGoldNFT);
    }

    function pause(bool _status) external onlyOwner returns (bool) {
        int256 _goldPrice = getLatestGoldPriceOunce();
        if (_status) {
            require(_goldPrice == 0, "gold price is not zero");
        } else {
            require(_goldPrice > 0, "gold price is zero");
        }
        isPaused = _status;
        return (_status);
    }

    function setPhysicalGoldFee(uint256 newFeeLocal, uint256 newFeeSwiss)
        external
        onlyOwner
    {
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
        int256 pricePerGram = (getLatestGoldPriceOunce() * 1e8) / 3110347680; // Multiplied by 10^8 to handle decimals

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

    function removeGoldReserve(uint256 amountGold) external onlyAdmin {
        goldReserve -= amountGold;
        emit goldReserved("Remove", amountGold, goldReserve);
    }

    function mintLiquidity(address _liquidityContract, uint256 _iGoldAmount) external onlyAdmin returns(uint256){
        require(
            totalSupply() <= goldReserve.mul(1e8).div(1e1),
            "gold reserve reached"
        );
        int256 goldPrice = getLatestGoldPriceGram();
        require(goldPrice > 0, "Invalid gold price");
        _mint(_liquidityContract, _iGoldAmount);
        return _iGoldAmount;
    }

    function burnLiquidity(address _liquidityContract, uint256 _iGoldAmount) external onlyMiner returns(uint256){
        _burn(_liquidityContract, _iGoldAmount);
        return _iGoldAmount;
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

        if (tokenAddress == address(0x0)) {
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
