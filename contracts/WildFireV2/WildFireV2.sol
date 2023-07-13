// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IWBNB} from "../IWBNB.sol";
import "hardhat/console.sol";

contract WildfireV2 is ReentrancyGuard, ERC1155Holder {
    address public tradeToken; // ERC1155 address
    address public payToken; // BNB address

    // Order Info for managing only maker and amount
    struct Order {
        address maker;
        uint256 orderAmount;
    }
    // Order Grid for managing by order
    struct OrderGrid {
        bytes32 nextOrderGridId; // next order grid id in OrderGridList/grids
        Order order;
    }
    // Order Grid list for managing by order
    struct OrderGridList {
        uint256 length;
        bytes32 headId;
        bytes32 tailId;
        mapping(bytes32 => OrderGrid) grids; // bytes32 : unique id for OrderGrid
    }
    // Price Grid for managing by price
    struct PriceGrid {
        uint256 price;
        uint256 priceAmount;
    }
    // Order-Price Grid for managing combination with order and price
    struct OrderPriceGrid {
        bytes32 orderId;
        uint256 orderPrice;
        uint256 orderAmount;
    }
    struct OrderPriceGridList {
        mapping(address => OrderPriceGrid[]) orders; // address : orderMaker address
        mapping(bytes32 => uint256) orderIndexes; // bytes32 : orderId
    }

    enum SellOrBuy {
        Sell,
        Buy
    }
    PriceGrid[] private sellPrices; // sell price list
    PriceGrid[] private buyPrices; // buy price list
    OrderPriceGridList private sellOrders; // sell order list
    OrderPriceGridList private buyOrders; // buy order list

    // depositAmountByUser[userAddress][tokenAddress] => depositAmount
    mapping(address => mapping(address => uint256)) public depositAmountByUser; // address(1st parameter) : user address, address(2nd parameter) : token address

    // orderBook[tokenAddress][price] => orders[maker, orderAmount]
    mapping(address => mapping(uint256 => OrderGridList)) public orderBook; // address(1st parameter) : token address, uint256(2nd parameter) : price

    event OrderCreated();
    event OrderFilled();
    event OrderPartiallyFilled();
    event OrderCancelled();

    constructor(address _tradeToken, address _payToken) {
        tradeToken = _tradeToken; // ERC1155 token address
        payToken = _payToken; // USDC address
    }

    /**
     * Create an order to sell the token.
     * should init price grid before call this at first
     * @param _price desired price
     * @param _sellAmount sell token amount
     * @param _epochId _epochId of ERC1155 token
     *
     */
    function createSellOrder(
        uint256 _price,
        uint256 _sellAmount,
        uint256 _epochId
    ) external returns (bool) {
        require(_price > 0, "Price should be greater than zero");
        require(_sellAmount > 0, "SellAmount should be greater than zero");

        (bool isExistingPrice, uint256 _priceIndex) = getIndexOfPrice(
            _price,
            SellOrBuy.Sell
        );
        if (!isExistingPrice) {
            initPriceGrid(_price);
            (, _priceIndex) = getIndexOfPrice(_price, SellOrBuy.Sell);
        }

        require(
            sellPrices[_priceIndex].price == _price &&
                buyPrices[_priceIndex].price == _price,
            "Price does not match the index"
        );
        bytes32 orderId;

        deposit(tradeToken, _price, _sellAmount, _epochId);
        // new sell order
        if (orderBook[tradeToken][_price].length == 0) {
            orderId = initOrderGridList(
                orderBook[tradeToken][_price],
                msg.sender,
                _sellAmount
            );
        } else {
            orderId = addOrderGridList(
                orderBook[tradeToken][_price],
                msg.sender,
                _sellAmount
            );
        }
        addOrderGridList(
            orderBook[tradeToken][_price],
            msg.sender,
            _sellAmount
        );
        addOrderPriceGridList(
            sellOrders,
            msg.sender,
            orderId,
            _price,
            _sellAmount
        );
        addPriceAmount(sellPrices, _priceIndex, _sellAmount);

        emit OrderCreated();

        return true;
    }

    function fulfillSellOrder(
        address _maker,
        uint256 _price,
        uint256 _sellAmount,
        uint256 _priceIndex,
        uint256 _epochId
    ) public returns (bool) {
        require(_price > 0, "Price should be greater than zero");
        require(_sellAmount > 0, "SellAmount should be greater than zero");

        uint256 buyOrderListLength = orderBook[payToken][_price].length;
        for (uint8 i = 0; i < buyOrderListLength; i++) {
            bytes32 head_ = orderBook[payToken][_price].headId;
            uint256 buyAmount = orderBook[payToken][_price]
                .grids[head_]
                .order
                .orderAmount;

            if (_sellAmount >= buyAmount) {
                Order memory o = orderBook[payToken][_price].grids[head_].order;
                popHead(orderBook[payToken][_price]);
                deleteOrderPriceGridList(buyOrders, o.maker, head_);
                subPriceAmount(buyPrices, _priceIndex, o.orderAmount);

                depositAmountByUser[o.maker][payToken] -=
                    o.orderAmount *
                    _price;
                depositAmountByUser[_maker][tradeToken] -= o.orderAmount;

                IWBNB(payToken).transfer(_maker, o.orderAmount * _price);
                IERC1155(tradeToken).safeTransferFrom(
                    address(this),
                    o.maker,
                    _epochId,
                    o.orderAmount,
                    ""
                );
                _sellAmount -= o.orderAmount;

                emit OrderPartiallyFilled();
            } else if (buyAmount > _sellAmount) {
                Order memory o = orderBook[payToken][_price].grids[head_].order;
                orderBook[payToken][_price]
                    .grids[head_]
                    .order
                    .orderAmount -= _sellAmount;

                subOrderAmount(buyOrders, o.maker, head_, _sellAmount);
                subPriceAmount(buyPrices, _priceIndex, _sellAmount);

                depositAmountByUser[o.maker][payToken] -= _sellAmount * _price;
                depositAmountByUser[_maker][tradeToken] -= _sellAmount;

                IWBNB(payToken).transfer(_maker, (_price * _sellAmount));
                IERC1155(tradeToken).safeTransferFrom(
                    address(this),
                    o.maker,
                    _epochId,
                    _sellAmount,
                    ""
                );
                _sellAmount = 0;

                emit OrderFilled();
            }
        }
        return true;
    }

    /**
     * Create an order to buy token.
     *
     * @param _price desired price
     * @param _buyAmount buy token amount
     *
     */
    function createBuyOrder(
        uint256 _price,
        uint256 _buyAmount
    ) external returns (bool) {
        require(_price > 0, "Price should be greater than zero");
        require(_buyAmount > 0, "SellAmount should be greater than zero");

        (bool isExistingPrice, uint256 _priceIndex) = getIndexOfPrice(
            _price,
            SellOrBuy.Buy
        );
        if (!isExistingPrice) {
            initPriceGrid(_price);
            (, _priceIndex) = getIndexOfPrice(_price, SellOrBuy.Buy);
        }

        require(
            sellPrices[_priceIndex].price == _price &&
                buyPrices[_priceIndex].price == _price,
            "Price does not match the index"
        );
        bytes32 orderId;

        deposit(payToken, _price, _buyAmount, 0);
        // new buy order
        if (orderBook[payToken][_price].length == 0) {
            orderId = initOrderGridList(
                orderBook[payToken][_price],
                msg.sender,
                _buyAmount
            );
        } else {
            orderId = addOrderGridList(
                orderBook[payToken][_price],
                msg.sender,
                _buyAmount
            );
        }
        addOrderGridList(orderBook[payToken][_price], msg.sender, _buyAmount);
        addOrderPriceGridList(
            buyOrders,
            msg.sender,
            orderId,
            _price,
            _buyAmount
        );
        addPriceAmount(buyPrices, _priceIndex, _buyAmount);

        emit OrderCreated();

        return true;
    }

    function fulfillBuyOrder(
        address _maker,
        uint256 _price,
        uint256 _buyAmount,
        uint256 _priceIndex,
        uint256 _epochId
    ) public returns (bool) {
        require(_price > 0, "Price should be greater than zero");
        require(_buyAmount > 0, "SellAmount should be greater than zero");

        uint256 sellOrderListLength = orderBook[tradeToken][_price].length;
        for (uint8 i = 0; i < sellOrderListLength; i++) {
            bytes32 head_ = orderBook[tradeToken][_price].headId;
            uint256 sellAmount = orderBook[tradeToken][_price]
                .grids[head_]
                .order
                .orderAmount;

            if (_buyAmount >= sellAmount) {
                Order memory o = orderBook[tradeToken][_price]
                    .grids[head_]
                    .order;
                popHead(orderBook[tradeToken][_price]);
                deleteOrderPriceGridList(sellOrders, o.maker, head_);
                subPriceAmount(sellPrices, _priceIndex, o.orderAmount);

                depositAmountByUser[o.maker][tradeToken] -= o.orderAmount;
                depositAmountByUser[_maker][payToken] -= o.orderAmount * _price;

                IWBNB(payToken).transfer(o.maker, o.orderAmount * _price);
                IERC1155(tradeToken).safeTransferFrom(
                    address(this),
                    _maker,
                    _epochId,
                    o.orderAmount,
                    ""
                );
                _buyAmount -= o.orderAmount;

                emit OrderPartiallyFilled();
            } else if (sellAmount > _buyAmount) {
                Order memory o = orderBook[tradeToken][_price]
                    .grids[head_]
                    .order;
                orderBook[tradeToken][_price]
                    .grids[head_]
                    .order
                    .orderAmount -= _buyAmount;

                subOrderAmount(sellOrders, o.maker, head_, _buyAmount);
                subPriceAmount(sellPrices, _priceIndex, _buyAmount);

                depositAmountByUser[o.maker][tradeToken] -= _buyAmount;
                depositAmountByUser[_maker][payToken] -= _buyAmount * _price;

                IWBNB(payToken).transfer(o.maker, (_price * _buyAmount));
                IERC1155(tradeToken).safeTransferFrom(
                    address(this),
                    _maker,
                    _epochId,
                    _buyAmount,
                    ""
                );
                _buyAmount = 0;

                emit OrderFilled();
            }
        }

        return true;
    }

    /**
     * Cancel the sell order.
     *
     * @param _price  price to cancel order
     * @param _orderId order id to cancel order
     * @param _priceIndex index of price list
     * @param _epochId _epochId of ERC1155 token
     *
     */
    function cancelSellOrder(
        uint256 _price,
        bytes32 _orderId,
        uint256 _priceIndex,
        uint256 _epochId
    ) external returns (bool) {
        require(
            sellPrices[_priceIndex].price == _price &&
                buyPrices[_priceIndex].price == _price,
            "Price does not match the index"
        );

        Order memory order = orderBook[tradeToken][_price]
            .grids[_orderId]
            .order;
        require(order.maker == msg.sender, "Only maker can cancell the order");

        Refund(tradeToken, order.orderAmount, _epochId);

        deleteOrderGridList(orderBook[tradeToken][_price], _orderId);
        deleteOrderPriceGridList(sellOrders, msg.sender, _orderId);
        subPriceAmount(sellPrices, _priceIndex, order.orderAmount);

        emit OrderCancelled();

        return true;
    }

    /**
     * Cancel the buy order.
     *
     * @param _price  price to cancel order
     * @param _orderId order id to cancel order
     * @param _priceIndex index of price list
     *
     */
    function cancelBuyOrder(
        uint256 _price,
        bytes32 _orderId,
        uint256 _priceIndex
    ) external returns (bool) {
        require(
            sellPrices[_priceIndex].price == _price &&
                buyPrices[_priceIndex].price == _price,
            "Price does not match the index"
        );

        Order memory order = orderBook[payToken][_price].grids[_orderId].order;
        require(order.maker == msg.sender, "Only maker can cancell the order");

        Refund(payToken, order.orderAmount, 0);

        deleteOrderGridList(orderBook[payToken][_price], _orderId);
        deleteOrderPriceGridList(buyOrders, msg.sender, _orderId);
        subPriceAmount(buyPrices, _priceIndex, order.orderAmount);

        emit OrderCancelled();

        return true;
    }

    /**
     * Deposit token to this contract
     *
     * @param _token  deposit token address
     * @param _price deposit token price
     * @param _amount deposit token amount
     * @param _epochId epochId for ERC1155 token
     *
     */
    function deposit(
        address _token,
        uint256 _price,
        uint256 _amount,
        uint256 _epochId
    ) private returns (bool) {
        require(
            _token == tradeToken || _token == payToken,
            "Deposited token is not supported token type"
        );
        if (_token == tradeToken) {
            IERC1155(tradeToken).safeTransferFrom(
                msg.sender,
                address(this),
                _epochId,
                _amount,
                ""
            );
        } else if (_token == payToken) {
            IWBNB(payToken).transferFrom(
                msg.sender,
                address(this),
                _amount * _price
            );
        }
        depositAmountByUser[msg.sender][_token] += _amount;
        return true;
    }

    /**
     * Refund token from this contract
     *
     * @param _token  deposit token address
     * @param _amount deposit token amount
     * @param _epochId epochId for ERC1155 token
     *
     */
    function Refund(
        address _token,
        uint256 _amount,
        uint256 _epochId
    ) private returns (bool) {
        require(
            _token == tradeToken || _token == payToken,
            "Deposited token is not supported token type"
        );

        require(
            depositAmountByUser[msg.sender][_token] >= _amount,
            "Refund amount exceeds deposited"
        );

        if (_token == tradeToken) {
            IERC1155(tradeToken).safeTransferFrom(
                address(this),
                msg.sender,
                _epochId,
                _amount,
                ""
            );
        } else if (_token == payToken) {
            IWBNB(payToken).transfer(msg.sender, _amount);
        }
        depositAmountByUser[msg.sender][_token] -= _amount;
        return true;
    }

    // PriceGrid Helper functions
    /****************************************************************************************/
    /**
     * Initiate PriceGrid with specific price
     *
     * @param _price speicific price
     *
     */
    function initPriceGrid(uint256 _price) public {
        require(
            orderBook[tradeToken][_price].tailId == "" &&
                orderBook[payToken][_price].tailId == "",
            "Price already exist in orderbook"
        );
        sellPrices.push(PriceGrid(_price, 0));
        buyPrices.push(PriceGrid(_price, 0));
    }

    /**
     * Add priceAmount of PriceGrid
     *
     * @param _pGrid PriceGrid array
     * @param _index _index of price array
     * @param _changeAmount add amount
     *
     */
    function addPriceAmount(
        PriceGrid[] storage _pGrid,
        uint256 _index,
        uint256 _changeAmount
    ) private returns (bool) {
        _pGrid[_index].priceAmount += _changeAmount;
        return true;
    }

    /**
     * Subtract priceAmount of PriceGrid
     *
     * @param _pGrid PriceGrid array
     * @param _index _index of price array
     * @param _changeAmount add amount
     *
     */
    function subPriceAmount(
        PriceGrid[] storage _pGrid,
        uint256 _index,
        uint256 _changeAmount
    ) private returns (bool) {
        _pGrid[_index].priceAmount -= _changeAmount;
        return true;
    }

    /**
     * Get price grid index with specific price
     *
     * @param _price speicific price
     * @param _key sell or buy
     *
     */
    function getIndexOfPrice(
        uint256 _price,
        SellOrBuy _key
    ) public view returns (bool, uint256) {
        if (_key == SellOrBuy.Sell) {
            for (uint256 i = 0; i < sellPrices.length; i++) {
                if (sellPrices[i].price == _price) {
                    return (true, i);
                }
            }
        } else {
            for (uint256 i = 0; i < buyPrices.length; i++) {
                if (buyPrices[i].price == _price) {
                    return (true, i);
                }
            }
        }
        return (false, 0);
    }

    function getPriceAmount()
        external
        view
        returns (PriceGrid[] memory, PriceGrid[] memory)
    {
        return (sellPrices, buyPrices);
    }

    // OrderGridList Helper functions
    /****************************************************************************************/
    /**
     * Initiate OrderGridList with a new order
     *
     * @param _orderGridList OrderGridList
     * @param _maker maker of a new order
     * @param _amount amount of a new order
     *
     */
    function initOrderGridList(
        OrderGridList storage _orderGridList,
        address _maker,
        uint256 _amount
    ) private returns (bytes32) {
        Order memory order = Order(_maker, _amount);
        OrderGrid memory orderGrid = OrderGrid(0, order);

        bytes32 id = keccak256(
            abi.encodePacked(
                _maker,
                _amount,
                _orderGridList.length,
                block.timestamp
            )
        );
        _orderGridList.length = 1;
        _orderGridList.headId = id;
        _orderGridList.tailId = id;
        _orderGridList.grids[id] = orderGrid;

        return id;
    }

    /**
     * Add a new order to OrderGridList
     *
     * @param _orderGridList OrderGridList
     * @param _maker maker of a new order
     * @param _amount amount of a new order
     *
     */
    function addOrderGridList(
        OrderGridList storage _orderGridList,
        address _maker,
        uint256 _amount
    ) private returns (bytes32) {
        Order memory order = Order(_maker, _amount);
        OrderGrid memory orderGrid = OrderGrid(0, order);

        bytes32 id = keccak256(
            abi.encodePacked(
                _maker,
                _amount,
                _orderGridList.length,
                block.timestamp
            )
        );
        _orderGridList.length += 1;
        _orderGridList.tailId = id;
        _orderGridList.grids[id] = orderGrid;
        _orderGridList.grids[_orderGridList.tailId].nextOrderGridId = id;
        return id;
    }

    function deleteOrderGridList(
        OrderGridList storage _orderGridList,
        bytes32 _id
    ) private returns (bool) {
        if (_orderGridList.headId == _id) {
            require(
                _orderGridList.grids[_id].order.maker == msg.sender,
                "Unauthorised to delete this order."
            );
            popHead(_orderGridList);
            return true;
        }

        bytes32 curr = _orderGridList
            .grids[_orderGridList.headId]
            .nextOrderGridId;
        bytes32 prev = _orderGridList.headId;

        for (uint256 i = 1; i < _orderGridList.length; i++) {
            if (curr == _id) {
                require(
                    _orderGridList.grids[_id].order.maker == msg.sender,
                    "Unauthorised to delete this order."
                );
                _orderGridList.grids[prev].nextOrderGridId = _orderGridList
                    .grids[curr]
                    .nextOrderGridId;
                delete _orderGridList.grids[curr];
                _orderGridList.length -= 1;
                return true;
            }
            prev = curr;
            curr = _orderGridList.grids[prev].nextOrderGridId;
        }
        revert("Order ID not found.");
    }

    function popHead(
        OrderGridList storage _orderGridList
    ) private returns (bool) {
        bytes32 currHead = _orderGridList.headId;
        _orderGridList.headId = _orderGridList.grids[currHead].nextOrderGridId;
        delete _orderGridList.grids[currHead];
        _orderGridList.length -= 1;
        return true;
    }

    // OrderPriceGrid Helper functions
    /****************************************************************************************/
    /**
     * Add new order to OrderPriceGridList
     *
     * @param _list OrderPriceGridList
     * @param _maker maker of a new order
     * @param _orderId orderid of a new order
     * @param _price price of a new order
     * @param _amount amount of a new order
     *
     */
    function addOrderPriceGridList(
        OrderPriceGridList storage _list,
        address _maker,
        bytes32 _orderId,
        uint256 _price,
        uint256 _amount
    ) private returns (bool) {
        if (_list.orderIndexes[_orderId] == 0) {
            _list.orders[_maker].push(
                OrderPriceGrid(_orderId, _price, _amount)
            );
            _list.orderIndexes[_orderId] = _list.orders[_maker].length;
            return true;
        } else {
            return false;
        }
    }

    function deleteOrderPriceGridList(
        OrderPriceGridList storage _list,
        address _maker,
        bytes32 _orderId
    ) private returns (bool) {
        uint256 orderIdIndex = _list.orderIndexes[_orderId];

        if (orderIdIndex != 0) {
            uint256 toDeleteIndex = orderIdIndex - 1;
            uint256 lastIndex = _list.orders[_maker].length - 1;

            if (lastIndex != toDeleteIndex) {
                OrderPriceGrid memory lastGrid = _list.orders[_maker][
                    lastIndex
                ];
                _list.orders[_maker][toDeleteIndex] = lastGrid;
                _list.orderIndexes[lastGrid.orderId] = orderIdIndex;
            }
            _list.orders[_maker].pop();
            delete _list.orderIndexes[_orderId];

            return true;
        } else {
            return false;
        }
    }

    function addOrderAmount(
        OrderPriceGridList storage _list,
        address _maker,
        bytes32 _orderId,
        uint256 _amount
    ) private returns (bool) {
        uint256 orderIdIndex = _list.orderIndexes[_orderId];

        if (orderIdIndex != 0) {
            _list.orders[_maker][orderIdIndex - 1].orderAmount += _amount;
            return true;
        } else {
            return false;
        }
    }

    function subOrderAmount(
        OrderPriceGridList storage _list,
        address _maker,
        bytes32 _orderId,
        uint256 _amount
    ) private returns (bool) {
        uint256 orderIdIndex = _list.orderIndexes[_orderId];

        if (orderIdIndex != 0) {
            _list.orders[_maker][orderIdIndex - 1].orderAmount -= _amount;
            return true;
        } else {
            return false;
        }
    }
}
