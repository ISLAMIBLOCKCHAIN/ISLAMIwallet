// SPDX-License-Identifier: MIT

/*
@dev: P2P smart contract ISLAMI P2P V 1.1
*/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

pragma solidity = 0.8.19;
   using SafeMath for uint256;
 
   uint256 constant MAX_UINT = 2**256 - 1;
   

interface IDODOV2 {
    function querySellBase(
        address trader, 
        uint256 payBaseAmount
    ) external view  returns (uint256 receiveQuoteAmount,uint256 mtFee);

    function querySellQuote(
        address trader, 
        uint256 payQuoteAmount
    ) external view  returns (uint256 receiveBaseAmount,uint256 mtFee);
}

interface IDODOProxy {

    function dodoSwapV2TokenToToken(
        address fromToken,
        address toToken,
        uint256 fromTokenAmount,
        uint256 minReturnAmount,
        address[] memory dodoPairs,
        uint256 directions,
        bool isIncentive,
        uint256 deadLine
    ) external returns (uint256 returnAmount);
}

contract Swap{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address constant public burn = 0x000000000000000000000000000000000000dEaD;

    uint256 public slippage = 1;
    uint256 public burned;

    function getPriceBuy(address _pool, address _sender, uint256 _amount, uint256 _slippage) public view returns(uint256 _Price){
        (uint256 receivedBaseAmount,) = IDODOV2(_pool).querySellQuote(_sender, _amount);
        uint256 minReturnAmount = receivedBaseAmount.mul(100 - _slippage).div(100);
        return(minReturnAmount);
    }
    function getPriceSell(address _pool, address _sender, uint256 _amount, uint256 _slippage) public view returns(uint256 _Price){
        (uint256 receivedQuoteAmount,) = IDODOV2(_pool).querySellBase(_sender, _amount);
        uint256 minReturnAmount = receivedQuoteAmount.mul(100 - _slippage).div(100);
        return(minReturnAmount);
    }

    address USDCpool = 0x9723520d16690075e80cd8108f7C474784F96bCe; //ISLAMI pool on DODO
    address USDTpool = 0x14afbB9E6Ab4Ab761f067fA131e46760125301Fc;
    address USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address dodoApprove = 0x6D310348d5c12009854DFCf72e0DF9027e8cb4f4; //Dodo Approve Address
    address dodoProxy = 0xa222e6a71D1A1Dd5F279805fbe38d5329C1d0e70; //Dodo proxy address

    function useDodoSwapV2(address _owner, address fromToken, address toToken, uint256 _amount, uint256 _slippage, uint256 directions) internal {
        address dodoV2Pool = 0x9723520d16690075e80cd8108f7C474784F96bCe;
        if(fromToken == USDT || toToken == USDT){
            dodoV2Pool = USDTpool;
        }
        uint256 minAmount;
        if(_slippage < slippage){
            _slippage = slippage;
        }
        // check swap if buy or sell
        IERC20(fromToken).transferFrom(msg.sender, address(this), _amount);
        if(directions == 0 || directions == 1){
            minAmount = getPriceBuy(dodoV2Pool, msg.sender, _amount, slippage);
        }
        else{
            minAmount = getPriceSell(dodoV2Pool, msg.sender, _amount, slippage);
        }
        //check dodo pair
        address[] memory dodoPairs = new address[](1); //one-hop
        dodoPairs[0] = dodoV2Pool;
        //set dead line
        uint256 deadline = block.timestamp + 60 * 10;
        //approve tokens 
        _generalApproveMax(fromToken, dodoApprove, _amount);
        // get return amount
        uint256 returnAmount = IDODOProxy(dodoProxy).dodoSwapV2TokenToToken(
            fromToken,
            toToken,
            _amount,
            minAmount,
            dodoPairs,
            directions,
            false,
            deadline
        );
        if(_owner == burn){
            IERC20(toToken).safeTransfer(burn, returnAmount);
            burned += returnAmount;
        }
        else{
            IERC20(toToken).safeTransfer(msg.sender, returnAmount);
        }
    }
    function _generalApproveMax(
        address token,
        address to,
        uint256 amount
    ) internal {
        uint256 allowance = IERC20(token).allowance(address(this), to);
        if (allowance < amount) {
            if (allowance > 0) {
                IERC20(token).safeApprove(to, 0);
            }
            IERC20(token).safeApprove(to, MAX_UINT);
        }
    }
}
contract ISLAMIp2p_V1_1 is Swap {

/*
@dev: Private values
*/  
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    address public feeReceiver;
    

    IERC20 ISLAMI = IERC20(0x9c891326Fd8b1a713974f73bb604677E1E63396D);

    uint256 public orN; //represents order number created
    uint256 public sellOrders;
    uint256 public buyOrders;
    uint256 public totalOrders;
    uint256 public maxOrders = 60;
    uint256 public canceledOrders;
    uint256 public ISLAMIinOrder;
    uint256 public USDinOrder;
    
    uint256 private maxISLAMI;
    uint256 constant private ISLAMIdcml = 10**7;
    //uint256 constant private USDdcml = 10**6;

    uint256 public activationFee = 1000*10**7;
    uint256 public p2pFee = 1;
    uint256 public feeFactor = 1000;
    uint256 public feeInUSDT = 1 * 10 ** 6;
    uint256 public range = 30;

    struct orderDetails{
        uint256 orderType; // 1 = sell , 2 = buy
        uint256 orderNumber;
        address sB; //seller or buyer
        IERC20 orderCurrency;
        uint256 remainAmount;
        uint256 orderPrice;
        uint256 remainCurrency;
        uint256 dateCreated;
        uint256 orderLife;
        bool orderStatus; // represents if order is completed or not
    }
    struct userHistory{
        uint256 ordersCount;
        uint256 sold;
        uint256 bought;
    }

    event orderCreated(address OrderOwner, uint256 Type, uint256 Amount, uint256 Price, IERC20 Currency);
    event orderCancelled(address OrderOwner, uint256 Type);
    event orderFilled(address OrderOwner, uint256 Type);
    event orderBuy(address OrderOwner, address OrderTaker, uint256 Amount, uint256 Price);
    event orderSell(address OrderOwner, address OrderTaker, uint256 Amount, uint256 Price);
    event ISLAMIswap(string Type, uint256 Amount, address Swaper);

    mapping(address => orderDetails) public p2p;
    mapping(address => uint256) public monopoly;
    mapping(address => userHistory) public userOrders;
    mapping(address => bool) public canCreateOrder;
    mapping(address => bool) public isActivated;

    orderDetails[] public OrderDetails;
    /*
    @dev: prevent reentrancy when function is executed
*/
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    constructor(){
        feeReceiver = msg.sender;
        orN = 0;
        maxISLAMI = 33000 * ISLAMIdcml;
    }
    function setMaxISLAMI(uint256 _newMax) external{
        require(msg.sender == feeReceiver, "Not authorized to change Max");
        maxISLAMI = _newMax * ISLAMIdcml;
    }
    function ISLAMIprice1() public view returns(uint256 _price){
        _price = getPriceSell(USDTpool, address(this), 10000000, 1);
        return(_price);
    }
    function ISLAMIprice() public view returns(uint256 _price){
        _price = getPriceSell(USDCpool, address(this), 10000000, 1);
        return(_price);
    }
    function swapISLAMI(uint256 _type, address _currency, uint256 _amount, uint256 _slippage) external{
        string memory Type;
        address _fromToken;
        address _toToken;
        if(_type == 0 || _type == 1){
            Type = "Buy";
            _fromToken = _currency;
            _toToken = address(ISLAMI);
        }
        else{
            Type = "Sell";
            _fromToken = address(ISLAMI);
            _toToken = _currency;
            require(_amount <= maxISLAMI, "Price impact is too high");
        }
        useDodoSwapV2(msg.sender, _fromToken, _toToken, _amount, _slippage, _type);
        emit ISLAMIswap(Type, _amount, msg.sender);
    }
    function changeFee(uint256 _activationFee, uint256 _p2pFee, uint256 _feeFactor) external {
        require(msg.sender == feeReceiver, "Not authorized to change fee");
        require(_p2pFee >= 1 && _feeFactor >= 100,"Fee can't be zero");
        activationFee = _activationFee.mul(ISLAMIdcml);
        p2pFee = _p2pFee;
        feeFactor = _feeFactor;
    }
    function changeRange(uint256 _range) external{
        require(msg.sender == feeReceiver, "Not authorized to change fee");
        range = _range;
    }
    function activateP2P() external nonReentrant{
        require(isActivated[msg.sender] != true, "User P2P is already activated!");
        if(ISLAMI.balanceOf(msg.sender) >= activationFee){
            //require approve from ISLAMI smart contract
            ISLAMI.transferFrom(msg.sender, burn, activationFee);
            burned += activationFee;
        }
        else{
            require(IERC20(USDT).balanceOf(msg.sender) >= feeInUSDT, "need 1 USDT to activate p2p");
            //require approve from USDT smart contract
            useDodoSwapV2(burn, USDT, address(ISLAMI), feeInUSDT, 1, 1);
        }
        
        canCreateOrder[msg.sender] = true;
        isActivated[msg.sender] = true;
    }
    //if updated keep ativated users
    function byPassP2P(address[] memory _user) external{
        require(msg.sender == feeReceiver, "not admin");
        for(uint i = 1; i < _user.length; i++){
            canCreateOrder[_user[i]] = true;
            isActivated[_user[i]] = true;
        }
    }
    function createOrder(
        uint256 _type, 
        uint256 _islamiAmount, 
        uint256 _price, 
        IERC20 _currency
        ) 
        public 
        nonReentrant
        {
        require(monopoly[msg.sender] < block.timestamp, "Monopoly not allowed");
        require(canCreateOrder[msg.sender] == true, "User have an active order");
        require(_type == 1 || _type == 2, "Type not found (Buy or Sell)");
        totalOrders++;
        orN++;
        uint256 islamiAmount = _islamiAmount.div(ISLAMIdcml);
        uint256 _currencyAmount = _price.mul(islamiAmount);
        uint256 _p2pFee;
        p2p[msg.sender].orderLife = block.timestamp.add(3 days);
        p2p[msg.sender].orderNumber = orN;
        p2p[msg.sender].sB = msg.sender;
        p2p[msg.sender].orderType = _type;
        p2p[msg.sender].dateCreated = block.timestamp;
        p2p[msg.sender].orderCurrency = _currency;
        uint256 dexPrice = ISLAMIprice();
        uint256 _limit = dexPrice.mul(range).div(100);
        uint256 _up = dexPrice.add(_limit);
        uint256 _down = dexPrice.sub(_limit);
        require(_price < _up && _price > _down, "behing range");
        p2p[msg.sender].orderPrice = _price;
        if(_type == 1){ //sell ISLAMI
            p2p[msg.sender].remainAmount = _islamiAmount;
            _p2pFee = _islamiAmount.mul(p2pFee).div(feeFactor);
            //require approve from ISLAMICOIN contract
            ISLAMI.transferFrom(msg.sender, address(this), _islamiAmount);
            ISLAMI.transferFrom(msg.sender, burn, _p2pFee);
            ISLAMIinOrder += _islamiAmount;
            sellOrders++;
            burned += _p2pFee;
        }
        else if(_type == 2){ //buy ISLAMI
            p2p[msg.sender].remainCurrency = _currencyAmount;
            _p2pFee = _currencyAmount.mul(p2pFee).div(feeFactor);
            _currency.transferFrom(msg.sender, address(this), _currencyAmount);
            //_currency.transferFrom(msg.sender, feeReceiver, _p2pFee);
            useDodoSwapV2(burn, address(_currency), address(ISLAMI), _p2pFee, 1,1);
            USDinOrder += _currencyAmount;
            buyOrders++;
        }
        OrderDetails.push(orderDetails
        (
                _type,
                orN, 
                msg.sender,
                _currency,
                _islamiAmount,
                _price,
                _currencyAmount,
                p2p[msg.sender].dateCreated,
                p2p[msg.sender].orderLife,
                false
                )
                );
        canCreateOrder[msg.sender] = false;
        userOrders[msg.sender].ordersCount++;
        emit orderCreated(msg.sender, _type, _islamiAmount, _price, _currency);
    }
    function getOrders() public view returns (orderDetails[] memory){
        return OrderDetails;
    }
    function getOrderIndex(address _orderOwner) public view returns(uint256 Index){
        uint256 _index = OrderDetails.length -1;
        if(OrderDetails[_index].sB == _orderOwner){
            return(_index);
        }
        else{
            for(uint i = 0; i< OrderDetails.length -1; i++){
            if(OrderDetails[i].sB == _orderOwner){
                return(i);
            }
        }
        }
    }
    function forOrders(uint256 _orderIndex, address _orderOwner) internal{
        fixOrders(_orderIndex);
        deleteOrder(_orderOwner);
        delete p2p[_orderOwner];
        canceledOrders++;
    }
    function fillOrder(uint256 _orderIndex, address _orderOwner) internal{
        forOrders(_orderIndex, _orderOwner);
        emit orderFilled(_orderOwner, p2p[_orderOwner].orderType);
    }
    function adminCancel(uint256 _orderIndex, address _orderOwner) external{
        require(msg.sender == feeReceiver, "not admin");
        forOrders(_orderIndex, _orderOwner);
        emit orderCancelled(_orderOwner, p2p[_orderOwner].orderType);
    }
    function forceCancel(uint256 _orderIndex, address _orderOwner) internal{
        forOrders(_orderIndex, _orderOwner);
        emit orderCancelled(_orderOwner, p2p[_orderOwner].orderType);
    }
    function superCancel() public{
        uint256 _orderCancelled = 0;
        for(uint i = 0; i < OrderDetails.length -1; i++){
            address _orderOwner = OrderDetails[i].sB;
            if(OrderDetails[i].orderLife < block.timestamp){
                fixOrders(i);
                deleteOrder(_orderOwner);
                canceledOrders++;
                _orderCancelled = 1;
                delete p2p[_orderOwner];
                canCreateOrder[_orderOwner] = true;
            }
        }
        if(_orderCancelled != 1){
            revert("Orders life is normal");
        }
    }
    function cancelOrder() external{
        uint256 _orderCancelled = 0;
        uint256 _orderIndex = OrderDetails.length -1;
        if(OrderDetails[_orderIndex].sB == msg.sender){
            forceCancel(_orderIndex, msg.sender);
        }
        else{
            for(uint i = 0; i < OrderDetails.length -1; i++){
            if(OrderDetails[i].sB == msg.sender){
                fixOrders(i);
                deleteOrder(msg.sender);
                _orderCancelled = 1;
                emit orderCancelled(msg.sender, p2p[msg.sender].orderType);
                monopoly[msg.sender] = block.timestamp.add(60);
                break;
            }
         }
         if(_orderCancelled != 1){
            revert("No user order found");
         }
         else{
            canceledOrders++;
         }
        }
    }
    //user can cancel order and retrive remaining amounts
    function deleteOrder(address _orderOwner) internal{
        if(p2p[_orderOwner].orderType == 1){
            uint256 amount = p2p[_orderOwner].remainAmount;
            if(amount > 0){
                ISLAMI.transfer(_orderOwner, amount);
            }
            sellOrders--;
        }
        else if(p2p[_orderOwner].orderType == 2){
            uint256 amount = p2p[_orderOwner].remainCurrency;
            if(amount > 0){
                IERC20 currency = p2p[_orderOwner].orderCurrency;
                currency.transfer(_orderOwner, amount);
            }
            buyOrders--;
        }
        delete p2p[_orderOwner];
        canCreateOrder[_orderOwner] = true; 
    }
    function fixOrders(uint256 _orderIndex) internal {
        OrderDetails[_orderIndex] = OrderDetails[OrderDetails.length - 1];
        OrderDetails.pop();
        totalOrders--;
    }
    function orderFill(address _orderOwner) internal{
        uint256 _orderIndex = OrderDetails.length -1;
        if(OrderDetails[_orderIndex].sB == _orderOwner){
            fillOrder(_orderIndex, _orderOwner);
        }
        else{
            for(uint i = 0; i < OrderDetails.length - 1; i++){
            if(OrderDetails[i].sB == _orderOwner){
                fillOrder(i, _orderOwner);
                break;
            }
        }
        }
    }
    //user can take full order or partial
    function takeOrder(address _orderOwner, uint256 _amount) external nonReentrant{
        IERC20 _currency = p2p[_orderOwner].orderCurrency;
        uint256 priceUSD = p2p[_orderOwner].orderPrice;
        uint256 amountUSD = _amount;//.mul(USDdcml);
        uint256 amountISLAMI = _amount;//.mul(ISLAMIdcml);
        uint256 toPay = _amount.div(ISLAMIdcml).mul(priceUSD);
        uint256 toReceive = amountUSD.mul(ISLAMIdcml).div(priceUSD);
        uint256 _p2pFee = amountISLAMI.mul(p2pFee).div(feeFactor);
        uint256 _index = getOrderIndex(_orderOwner);
        require(p2p[_orderOwner].orderStatus != true, "Order was completed");
        if(p2p[_orderOwner].orderType == 1){//Take sell
        require(amountISLAMI <= p2p[_orderOwner].remainAmount, "Seller has less ISLAMI than order");
        require(_currency.balanceOf(msg.sender) >= toPay, "Not enought USD");
        ISLAMI.transfer(burn, _p2pFee);
        ISLAMIinOrder -= amountISLAMI;
        burned += _p2pFee;
        //require approve from currency(USDT, USDC) contract
        _currency.transferFrom(msg.sender, _orderOwner, toPay); 
        ISLAMI.transfer(msg.sender, amountISLAMI.sub(_p2pFee));
        userOrders[msg.sender].bought += amountISLAMI;
        userOrders[_orderOwner].sold += amountISLAMI;
        p2p[_orderOwner].remainAmount -= amountISLAMI;
        OrderDetails[_index].remainAmount -= amountISLAMI;
          if(p2p[_orderOwner].remainAmount == 0){
                p2p[_orderOwner].orderStatus = true;
                orderFill(_orderOwner); 
            }
            emit orderBuy(_orderOwner, msg.sender, amountISLAMI, priceUSD);
        }
        else if(p2p[_orderOwner].orderType == 2){//Take buy
        require(amountUSD <= p2p[_orderOwner].remainCurrency, "Seller has less USD than order");
        require(ISLAMI.balanceOf(msg.sender) >= amountISLAMI, "Not enought ISLAMI");
        _p2pFee = amountUSD.mul(p2pFee).div(feeFactor);
        //_currency.transfer(feeReceiver, _p2pFee);
        //useDodoSwapV2(burn, address(_currency), address(ISLAMI), _p2pFee,1,1);
        USDinOrder -= amountUSD;
        //require approve from ISLAMICOIN contract
        ISLAMI.transferFrom(msg.sender, _orderOwner, toReceive);
        _currency.transfer(msg.sender, amountUSD);//.sub(_p2pFee));
        //require approve from _currency smart contract
        useDodoSwapV2(burn, address(_currency), address(ISLAMI), _p2pFee,1,1);
        userOrders[msg.sender].sold += toReceive;
        userOrders[_orderOwner].bought += toReceive;
        p2p[_orderOwner].remainCurrency -= amountUSD;
        OrderDetails[_index].remainCurrency -= amountUSD;
          if(p2p[_orderOwner].remainCurrency == 0){
                p2p[_orderOwner].orderStatus = true;
                orderFill(_orderOwner);
            }
            emit orderSell(_orderOwner, msg.sender, amountISLAMI, priceUSD);
        }
    }
}
 

               /*********************************************************
                  Proudly Developed by MetaIdentity ltd. Copyright 2023
               **********************************************************/
