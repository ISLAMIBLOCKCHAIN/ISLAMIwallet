// SPDX-License-Identifier: MIT

/*
@dev: This code is developed by Jaafar Krayem and is free to be used by anyone
Use under your own responsibility!
*/

/*
@dev: Receive ISLAMI for CryptoHalal Services
*/

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

pragma solidity = 0.8.15;

contract ISLAMI_CryptoHalal {
    using SafeMath for uint256;

    address public subscriptionReceiver;
    ERC20 public ISLAMI;

/*
@dev: Private values
*/  
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    uint256 constant private monthly = 30 days;

/*
@dev: public values
*/
    uint256 public subscriptionsCount;

/*
@dev: Events
*/
    event SubscriptionPaid(address Payee, uint256 SubscriptionTime);
    event receiverChange(address newReceiver);
/*
@dev: Subscriber Vault
*/   
    struct VaultSubscriptions{
        uint256 amountPaid;
        uint256 timeStart;
        uint256 subscriptionTime;
    }
/*

 @dev: Mappings
*/
    mapping(address => VaultSubscriptions) public Subscriptions;

/* @dev: Check if feReceiver */
    modifier onlyCryptoHalal (){
        require(msg.sender == subscriptionReceiver, "Only CryptoHalal owner can add change Subscriptions receiver");
        _;
    }
/*
    @dev: prevent reentrancy when function is executed
*/
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
    constructor(address _feeReceiver, ERC20 _ISLAMI) {
        ISLAMI = _ISLAMI;
        subscriptionReceiver = _feeReceiver;
        subscriptionsCount = 0;
        _status = _NOT_ENTERED;
    }
/*
   @dev: Change subscription receiver
*/
    function changeSubscriptionReceiver(address newReceiver) external onlyCryptoHalal{
        subscriptionReceiver = newReceiver;
        emit receiverChange(newReceiver);
    }
/*
   @dev: function for subscription payment
   Note: this function needs approval from ISLAMI contract
   for this contract as a spender.
*/
    function payForSubscription(uint256 _amount, uint256 _periodOfTime) external nonReentrant{
        uint256 periodOfTime = _periodOfTime.mul(monthly).add(block.timestamp);
        Subscriptions[msg.sender].amountPaid = _amount;
        Subscriptions[msg.sender].timeStart = block.timestamp;
        Subscriptions[msg.sender].subscriptionTime = periodOfTime;
        ISLAMI.transferFrom(msg.sender, subscriptionReceiver, _amount);
        subscriptionsCount++;
        emit SubscriptionPaid(msg.sender, periodOfTime);
    }

    function checkSubscription(address _subscriber) public view returns(bool){
        if(Subscriptions[_subscriber].subscriptionTime > block.timestamp){
            return true;
        }
        else{
            return false;
        }
    }
/*
   @dev: people who send Matic by mistake to the contract can withdraw them
*/
    mapping(address => uint) public balanceReceived;

    function receiveMoney() public payable {
        assert(balanceReceived[msg.sender] + msg.value >= balanceReceived[msg.sender]);
        balanceReceived[msg.sender] += msg.value;
    }

    function withdrawMoney(address payable _to, uint256 _amount) public {
        require(_amount <= balanceReceived[msg.sender], "not enough funds.");
        assert(balanceReceived[msg.sender] >= balanceReceived[msg.sender] - _amount);
        balanceReceived[msg.sender] -= _amount;
        _to.transfer(_amount);
    } 

    receive() external payable {
        receiveMoney();
    }
}


               /*********************************************************
                  Proudly Developed by MetaIdentity ltd. Copyright 2022
               **********************************************************/
