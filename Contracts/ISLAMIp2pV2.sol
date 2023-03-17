// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IDODOV2 {
    function dodoSwap(
        address fromToken,
        address toToken,
        uint256 fromTokenAmount,
        uint256 minReturnAmount,
        address[] calldata dodoPairs,
        uint256 directions,
        bool isIncentive,
        uint256 deadLine
    ) external returns (uint256 returnAmount);
}

contract ISLAMIp2pV2 {
    using SafeMath for uint256;

    address public owner;

    uint256 public orderIdCounter;
    IERC20 public islamiToken;
    IERC20 public usdtToken;
    address public dodoV2Contract;

    address public islamiTokenAddress;
    address public usdtTokenAddress;
    address public usdcTokenAddress;
    address public maticTokenAddress;

    address public admin;

    struct Order {
        uint256 id;
        address user;
        uint256 amount;
        bool isBuyOrder;
        bool isActive;
        uint256 price;
    }
    uint256 public tradeFeeNumerator = 1;
    uint256 public tradeFeeDenominator = 1000;
    uint256 public islamiActivationFee = 1000 * 10**7; // 1000 ISLAMI with 7 decimals
    uint256 public usdtActivationFee = 1 * 10**6; // 1 USDT with 6 decimals

    mapping(address => bool) public activatedUsers;

    mapping(uint256 => Order) public orders;

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only the contract owner can call this function"
        );
        _;
    }

    // Sorted order book
    uint256[] public buyOrderBook;
    uint256[] public sellOrderBook;

    constructor(address _islamiToken, address _usdtToken) {
        islamiToken = IERC20(_islamiToken);
        usdtToken = IERC20(_usdtToken);
        orderIdCounter = 1;
        owner = msg.sender;
        admin = msg.sender;
    }

    function changeFees(
        uint256 _tradeFeeNumerator,
        uint256 _tradeFeeDenominator,
        uint256 _islamiActivationFee,
        uint256 _usdtActivationFee
    ) external onlyOwner {
        tradeFeeNumerator = _tradeFeeNumerator;
        tradeFeeDenominator = _tradeFeeDenominator;
        islamiActivationFee = _islamiActivationFee;
        usdtActivationFee = _usdtActivationFee;
    }

    function swapTokens(
        address _fromToken,
        address _toToken,
        uint256 _fromTokenAmount,
        uint256 _minReturnAmount,
        uint256 _directions
    ) external {
        // Validate input tokens
        require(
            _fromToken == islamiTokenAddress ||
                _fromToken == usdtTokenAddress ||
                _fromToken == usdcTokenAddress ||
                _fromToken == maticTokenAddress,
            "Invalid input token"
        );

        require(
            _toToken == islamiTokenAddress ||
                _toToken == usdtTokenAddress ||
                _toToken == usdcTokenAddress ||
                _toToken == maticTokenAddress,
            "Invalid output token"
        );

        require(
            _fromToken != _toToken,
            "Input and output tokens must be different"
        );

        // Transfer the input tokens to the contract
        IERC20 fromToken = IERC20(_fromToken);
        require(
            fromToken.transferFrom(msg.sender, address(this), _fromTokenAmount),
            "Token transfer failed"
        );

        // Approve the DODO contract to spend the input tokens
        require(
            fromToken.approve(dodoV2Contract, _fromTokenAmount),
            "Token approve failed"
        );

        IDODOV2 dodo = IDODOV2(dodoV2Contract);

        address[] memory dodoPairs = new address[](1);
        dodoPairs[0] = address(0); // Use the default DODO pool

        uint256 deadline = block.timestamp + 600; // 10 minutes from now

        // Perform the swap
        uint256 returnAmount = dodo.dodoSwap(
            _fromToken,
            _toToken,
            _fromTokenAmount,
            _minReturnAmount,
            dodoPairs,
            _directions,
            false, // No incentive
            deadline
        );

        // Transfer the output tokens back to the user
        IERC20 toToken = IERC20(_toToken);
        require(
            toToken.transfer(msg.sender, returnAmount),
            "Token transfer failed"
        );
    }

    function activate(bool payInIslami) external {
        require(!activatedUsers[msg.sender], "User already activated");

        if (payInIslami) {
            require(
                islamiToken.transferFrom(
                    msg.sender,
                    address(this),
                    islamiActivationFee
                ),
                "ISLAMI token transfer failed"
            );
            _burnIslamiTokens(islamiActivationFee);
        } else {
            require(
                usdtToken.transferFrom(
                    msg.sender,
                    address(this),
                    usdtActivationFee
                ),
                "USDT transfer failed"
            );
            _swapAndBurnUSDT(usdtActivationFee);
        }

        activatedUsers[msg.sender] = true;
    }

    function _burnIslamiTokens(uint256 _amount) private {
        // Burn the tokens by sending them to the zero address
        require(
            islamiToken.transfer(address(0), _amount),
            "Failed to burn ISLAMI tokens"
        );
    }

    function _swapAndBurnUSDT(uint256 _usdtAmount) private {
        IDODOV2 dodo = IDODOV2(dodoV2Contract);

        // Approve the DODO contract to spend USDT tokens
        require(
            usdtToken.approve(dodoV2Contract, _usdtAmount),
            "USDT approve failed"
        );

        address[] memory dodoPairs = new address[](1);
        dodoPairs[0] = address(0); // Use the default DODO pool

        uint256 deadline = block.timestamp + 600; // 10 minutes from now

        // Perform the swap
        uint256 islamiAmount = dodo.dodoSwap(
            address(usdtToken),
            address(islamiToken),
            _usdtAmount,
            1, // Minimum return amount, you may want to adjust this value based on slippage tolerance
            dodoPairs,
            0, // Swap direction (0: USDT -> ISLAMI, 1: ISLAMI -> USDT)
            false, // No incentive
            deadline
        );

        // Burn the received ISLAMI tokens
        _burnIslamiTokens(islamiAmount);
    }

    function createOrder(
        uint256 _amount,
        bool _isBuyOrder,
        uint256 _price
    ) external {
        require(activatedUsers[msg.sender], "User not activated");
        require(_amount > 0, "Amount must be greater than 0");
        require(_price > 0, "Price must be greater than 0");

        uint256 usdtAmount = _amount.mul(_price).div(10**6); // Adjust the decimals between ISLAMI and USDT

        if (_isBuyOrder) {
            uint256 totalUSDT = usdtAmount; //.add(tradeFeeUSDT);
            require(
                usdtToken.transferFrom(msg.sender, address(this), totalUSDT),
                "USDT transfer failed"
            );
        } else {
            uint256 totalIslami = _amount;
            require(
                islamiToken.transferFrom(
                    msg.sender,
                    address(this),
                    totalIslami
                ),
                "ISLAMI token transfer failed"
            );
        }

        orders[orderIdCounter] = Order({
            id: orderIdCounter,
            user: msg.sender,
            amount: _amount,
            isBuyOrder: _isBuyOrder,
            isActive: true,
            price: _price
        });

        // Insert the order into the correct position in the order book
        if (_isBuyOrder) {
            _insertBuyOrder(orderIdCounter);
        } else {
            _insertSellOrder(orderIdCounter);
        }

        orderIdCounter = orderIdCounter.add(1);

        // Attempt to execute the trade
        _executeTrade();
    }

    function _insertBuyOrder(uint256 _orderId) private {
        // Insert the order into the buy order book in descending order
        if (buyOrderBook.length == 0) {
            buyOrderBook.push(_orderId);
            return;
        }

        for (uint256 i = 0; i < buyOrderBook.length; i++) {
            if (orders[_orderId].amount >= orders[buyOrderBook[i]].amount) {
                buyOrderBook.push(buyOrderBook[buyOrderBook.length - 1]);
                for (uint256 j = buyOrderBook.length - 1; j > i; j--) {
                    buyOrderBook[j] = buyOrderBook[j - 1];
                }
                buyOrderBook[i] = _orderId;
                return;
            }
        }

        buyOrderBook.push(_orderId);
    }

    function _insertSellOrder(uint256 _orderId) private {
        // Insert the order into the sell order book in ascending order
        if (sellOrderBook.length == 0) {
            sellOrderBook.push(_orderId);
            return;
        }

        for (uint256 i = 0; i < sellOrderBook.length; i++) {
            if (orders[_orderId].amount <= orders[sellOrderBook[i]].amount) {
                sellOrderBook.push(sellOrderBook[sellOrderBook.length - 1]);
                for (uint256 j = sellOrderBook.length - 1; j > i; j--) {
                    sellOrderBook[j] = sellOrderBook[j - 1];
                }
                sellOrderBook[i] = _orderId;
                return;
            }
        }

        sellOrderBook.push(_orderId);
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    function _executeTrade() private {
        while (buyOrderBook.length > 0 && sellOrderBook.length > 0) {
            Order storage buyOrder = orders[buyOrderBook[0]];
            Order storage sellOrder = orders[sellOrderBook[0]];

            // Check if the orders can be matched
            if (buyOrder.price >= sellOrder.price) {
                uint256 tradeAmount = _min(buyOrder.amount, sellOrder.amount);
                uint256 usdtAmount = tradeAmount.mul(sellOrder.price).div(
                    10**6
                ); // Adjust the decimals between ISLAMI and USDT

                // Calculate the fees
                uint256 islamiFee = tradeAmount.mul(tradeFeeNumerator).div(
                    tradeFeeDenominator
                );
                uint256 usdtFee = usdtAmount.mul(tradeFeeNumerator).div(
                    tradeFeeDenominator
                );

                // Transfer tokens between buyer and seller
                require(
                    islamiToken.transfer(
                        buyOrder.user,
                        tradeAmount.sub(islamiFee)
                    ),
                    "ISLAMI token transfer failed"
                );
                require(
                    usdtToken.transfer(sellOrder.user, usdtAmount.sub(usdtFee)),
                    "USDT transfer failed"
                );

                // Transfer fees to the burn
                _burnIslamiTokens(islamiFee);
                _swapAndBurnUSDT(usdtFee);

                // Update order amounts
                buyOrder.amount = buyOrder.amount.sub(tradeAmount);
                sellOrder.amount = sellOrder.amount.sub(tradeAmount);

                // Remove orders from the order books if fully executed
                if (buyOrder.amount == 0) {
                    buyOrder.isActive = false;
                    buyOrderBook = _removeOrderFromOrderBook(
                        buyOrderBook,
                        buyOrder.id
                    );
                }

                if (sellOrder.amount == 0) {
                    sellOrder.isActive = false;
                    sellOrderBook = _removeOrderFromOrderBook(
                        sellOrderBook,
                        sellOrder.id
                    );
                }
            } else {
                // Orders cannot be matched, break the loop
                break;
            }
        }
    }

    function _removeFirstElement(uint256[] storage arr)
        private
        returns (uint256[] storage)
    {
        for (uint256 i = 0; i < arr.length - 1; i++) {
            arr[i] = arr[i + 1];
        }
        arr.pop();
        return arr;
    }

    // Other functions

    function cancelOrder(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        require(order.user == msg.sender, "Not the owner of the order");
        require(order.isActive, "Order is not active");

        if (order.isBuyOrder) {
            require(
                islamiToken.transfer(order.user, order.amount),
                "Token transfer failed"
            );
            buyOrderBook = _removeOrderFromOrderBook(buyOrderBook, _orderId);
        } else {
            sellOrderBook = _removeOrderFromOrderBook(sellOrderBook, _orderId);
        }

        order.isActive = false;
    }

    function _removeOrderFromOrderBook(
        uint256[] storage orderBook,
        uint256 _orderId
    ) private returns (uint256[] storage) {
        uint256 indexToRemove;
        bool found = false;

        for (uint256 i = 0; i < orderBook.length; i++) {
            if (orderBook[i] == _orderId) {
                indexToRemove = i;
                found = true;
                break;
            }
        }

        require(found, "Order not found in the order book");

        for (uint256 i = indexToRemove; i < orderBook.length - 1; i++) {
            orderBook[i] = orderBook[i + 1];
        }

        orderBook.pop();
        return orderBook;
    }

    function getBuyOrderBook() external view returns (uint256[] memory) {
        return buyOrderBook;
    }

    function getSellOrderBook() external view returns (uint256[] memory) {
        return sellOrderBook;
    }

    function getOrder(uint256 _orderId) external view returns (Order memory) {
        return orders[_orderId];
    }

    function cancelAllOrders() external {
        require(msg.sender == admin, "Only admin can cancel all orders");

        for (uint256 i = 0; i < buyOrderBook.length; i++) {
            uint256 orderId = buyOrderBook[i];
            Order storage order = orders[orderId];

            if (order.isActive) {
                require(
                    islamiToken.transfer(order.user, order.amount),
                    "Token transfer failed"
                );
                order.isActive = false;
            }
        }

        for (uint256 i = 0; i < sellOrderBook.length; i++) {
            uint256 orderId = sellOrderBook[i];
            Order storage order = orders[orderId];

            if (order.isActive) {
                order.isActive = false;
            }
        }

        delete buyOrderBook;
        delete sellOrderBook;
    }
}
