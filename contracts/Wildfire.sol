// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract Wildfire is ReentrancyGuard, Ownable, ERC1155Holder {
    IERC1155 tradeToken; // ERC1155 address
    IERC20 payToken; // BNB address

    uint8 private SELL_ORDER = 0; // Sell order type
    uint8 private BUY_ORDER = 1; // Buy order type

    // Order struct
    struct OrderInfo {
        uint256 orderId; // urder id
        address token; // trade token address
        uint256 price; // desired price
        uint256 amount; //
        address creator; // maker / taker address by order type
        uint8 orderType; // sell / buy
        bool status; // if true order is ended, if false order is opened
    }

    // Arrays to store sell orders and buy orders
    OrderInfo[] public sellOrders;
    OrderInfo[] public buyOrders;
    uint256 public sellOrderCounts;
    uint256 public buyOrderCounts;

    event OrderCreated(uint256 orderId, address creator, uint8 orderType);
    event OrderCanceled(uint256 orderId, address operator, uint8 orderType);
    event OrderFulfilled(
        uint256 sellOrderId,
        uint256 buyOrderId,
        address seller,
        address buyer,
        uint256 price,
        uint256 amount
    );

    constructor(address _tradeToken, address _payToken) {
        tradeToken = IERC1155(_tradeToken); // ERC1155 token address
        payToken = IERC20(_payToken); // USDC address
    }

    /**
     * Create an order to sell the vault token.
     *
     * @param _sellToken sell token address
     * @param _price desired price
     * @param _amount sell token amount
     * @param _epochId epoch id in vault
     *
     */
    function createSellOrder(
        address _sellToken,
        uint256 _price,
        uint256 _amount,
        uint256 _epochId
    ) external nonReentrant {
        require(_sellToken != address(0), "_sellToken should not be zero");
        require(
            _sellToken == address(tradeToken),
            "_sellToken should be same with tradeToken"
        );
        require(_price > 0, "_price should be greater than zero");
        require(_amount != 0, "_price should be greater than zero");
        require(
            tradeToken.balanceOf(msg.sender, _epochId) >= _amount,
            "Insufficient balance"
        );

        sellOrderCounts++;

        OrderInfo memory newOrder = OrderInfo({
            orderId: sellOrderCounts,
            token: _sellToken,
            price: _price,
            amount: _amount,
            creator: msg.sender,
            orderType: SELL_ORDER,
            status: false
        });
        addOrderToList(newOrder);
        // IERC1155(_sellToken).setApprovalForAll(address(this), true);
        // IERC1155(_sellToken).safeTransferFrom(
        //     msg.sender,
        //     address(this),
        //     _epochId,
        //     _amount,
        //     ""
        // );

        emit OrderCreated(sellOrderCounts, msg.sender, SELL_ORDER);
    }

    /**
     * Create an order to buy the vault token.
     *
     * @param _buyToken buy token address
     * @param _price desired price
     * @param _amount buy token amount
     *
     */
    function createBuyOrder(
        address _buyToken,
        uint256 _price,
        uint256 _amount
    ) external nonReentrant {
        require(_buyToken != address(0), "_sellToken should not be zero");
        require(
            _buyToken == address(tradeToken),
            "_sellToken should be same with tradeToken"
        );
        require(_price > 0, "_price should be greater than zero");
        require(_amount != 0, "_price should be greater than zero");
        require(
            payToken.balanceOf(msg.sender) >= _price * _amount,
            "Insufficient balance"
        );

        buyOrderCounts++;

        OrderInfo memory newOrder = OrderInfo({
            orderId: buyOrderCounts,
            token: _buyToken,
            price: _price,
            amount: _amount,
            creator: msg.sender,
            orderType: BUY_ORDER,
            status: false
        });
        addOrderToList(newOrder);
        // IERC20(_buyToken).transferFrom(msg.sender, address(this), _amount);
        emit OrderCreated(buyOrderCounts, msg.sender, BUY_ORDER);
    }

    /**
     * Add created order to order list and sorted it as price
     *
     * @param _newOrder order info
     *
     */
    function addOrderToList(OrderInfo memory _newOrder) internal {
        if (_newOrder.orderType == 0) {
            uint256 i = sellOrders.length;
            sellOrders.push(_newOrder);
            while (i > 0 && sellOrders[i - 1].price > _newOrder.price) {
                sellOrders[i] = sellOrders[i - 1];
                i--;
            }
            sellOrders[i] = _newOrder;
        } else {
            uint256 i = buyOrders.length;
            buyOrders.push(_newOrder);
            while (i > 0 && buyOrders[i - 1].price < _newOrder.price) {
                buyOrders[i] = buyOrders[i - 1];
                i--;
            }
            buyOrders[i] = _newOrder;
        }
    }

    /**
     * Cancel the order by creator
     *
     * @param _orderId order id
     * @param _orderType order type - sell / buy
     *
     */
    function cancelOrder(uint256 _orderId, uint8 _orderType) external {
        require(
            _orderId <= sellOrderCounts || _orderType <= buyOrderCounts,
            "_orderId should be less than order counts"
        );
        OrderInfo storage order = _orderType == SELL_ORDER
            ? sellOrders[getSellOrderIndex(_orderId)]
            : buyOrders[getBuyOrderIndex(_orderId)];

        require(
            order.creator == msg.sender,
            "Only creator can cancell the order"
        );
        order.status = true;

        emit OrderCanceled(_orderId, msg.sender, _orderType);
    }

    /**
     * Match between suitable sell order and buy order
     *
     * @param _orderId order id
     * @param _orderType order type
     * @param _epochId epoch id
     *
     */
    function fullfillOrder(
        uint256 _orderId,
        uint8 _orderType,
        uint256 _epochId
    ) public nonReentrant {
        if (_orderType == SELL_ORDER) {
            OrderInfo storage sellOrder = sellOrders[_orderId];

            for (uint256 i = 1; i <= buyOrderCounts; i++) {
                OrderInfo storage buyOrder = buyOrders[i];

                if (sellOrder.price <= buyOrder.price && !buyOrder.status) {
                    uint256 tradeQuantity = sellOrder.amount < buyOrder.amount
                        ? sellOrder.amount
                        : buyOrder.amount;

                    uint256 tradeValue = tradeQuantity * sellOrder.price;

                    IERC1155(sellOrder.token).setApprovalForAll(
                        address(this),
                        true
                    );
                    IERC1155(sellOrder.token).safeTransferFrom(
                        sellOrder.creator,
                        buyOrder.creator,
                        _epochId,
                        tradeQuantity,
                        ""
                    );
                    IERC20(buyOrder.token).approve(address(this), tradeValue);
                    IERC20(buyOrder.token).transferFrom(
                        buyOrder.creator,
                        sellOrder.creator,
                        tradeValue
                    );

                    sellOrder.amount -= tradeQuantity;
                    if (sellOrder.amount == 0) {
                        sellOrder.status = true;
                    }
                    buyOrder.amount -= tradeValue;
                    if (buyOrder.amount == 0) {
                        buyOrder.status = true;
                    }

                    emit OrderFulfilled(
                        sellOrder.orderId,
                        buyOrder.orderId,
                        sellOrder.creator,
                        buyOrder.creator,
                        sellOrder.price,
                        tradeQuantity
                    );
                }
            }
        } else {
            OrderInfo storage buyOrder = buyOrders[_orderId];

            for (uint256 i = 1; i <= sellOrderCounts; i++) {
                OrderInfo storage sellOrder = sellOrders[i];

                if (sellOrder.price <= buyOrder.price && !sellOrder.status) {
                    uint256 tradeQuantity = buyOrder.amount < buyOrder.amount
                        ? sellOrder.amount
                        : buyOrder.amount;

                    uint256 tradeValue = tradeQuantity * sellOrder.price;

                    IERC1155(sellOrder.token).setApprovalForAll(
                        address(this),
                        true
                    );
                    IERC1155(sellOrder.token).safeTransferFrom(
                        sellOrder.creator,
                        buyOrder.creator,
                        _epochId,
                        tradeQuantity,
                        ""
                    );
                    IERC20(buyOrder.token).approve(address(this), tradeValue);
                    IERC20(buyOrder.token).transferFrom(
                        buyOrder.creator,
                        sellOrder.creator,
                        tradeValue
                    );

                    sellOrder.amount -= tradeQuantity;
                    if (sellOrder.amount == 0) {
                        sellOrder.status = true;
                    }
                    buyOrder.amount -= tradeValue;
                    if (buyOrder.amount == 0) {
                        buyOrder.status = true;
                    }

                    emit OrderFulfilled(
                        sellOrder.orderId,
                        buyOrder.orderId,
                        sellOrder.creator,
                        buyOrder.creator,
                        sellOrder.price,
                        tradeQuantity
                    );
                }
            }
        }
    }

    function getSellOrderIndex(uint256 _orderId) public view returns (uint256) {
        require(_orderId < sellOrders.length, "Order ID out of range");
        return _orderId;
    }

    function getBuyOrderIndex(uint256 _orderId) public view returns (uint256) {
        require(_orderId < buyOrders.length, "Order ID out of range");
        return _orderId;
    }
}
