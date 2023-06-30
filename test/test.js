const { expect } = require("chai");
const { ethers } = require("hardhat");
const { wbnbABI } = require("./abiCode.js");


describe("Wildfire", function () {
  let wbnbAddress = "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd";
  let wildfire;
  let tradeToken;
  let payToken;
  let owner;
  let maker;
  let taker;
  let sellPrice = ethers.utils.parseEther("0.5");
  let sellAmount = 10;
  let buyPrice = ethers.utils.parseEther("0.5");
  let buyAmount = 10;
  let epochId = 1;

  beforeEach(async function () {
    [owner, maker, taker, operator] = await ethers.getSigners();

    const TradeToken = await ethers.getContractFactory("VaultToken");
    tradeToken = await TradeToken.connect(owner).deploy("Vault Token", "Vault Token", "VT");
    await tradeToken.deployed();
    console.log("tradeToken address",tradeToken.address)

    payToken = await ethers.getContractAt(wbnbABI, wbnbAddress);
    console.log("payToken address",payToken.address)
    
    const Wildfire = await ethers.getContractFactory("Wildfire");
    wildfire = await Wildfire.deploy(tradeToken.address, payToken.address);
    await wildfire.deployed();
    console.log("wildfire address",wildfire.address)
  });

  it("should create a sell order", async function () {
    await tradeToken.mint(maker.address, epochId, sellAmount, {gasLimit : 50000});

    await expect(wildfire.connect(maker).createSellOrder(tradeToken.address, sellPrice, sellAmount, epochId)).to.emit(wildfire, "OrderCreated").withArgs(1, maker.address, 0);

    const sellOrder = await wildfire.sellOrders(0);
    expect(sellOrder.orderId).to.equal(1);
    expect(sellOrder.token).to.equal(tradeToken.address);
    expect(sellOrder.price).to.equal(sellPrice);
    expect(sellOrder.amount).to.equal(sellAmount);
    expect(sellOrder.creator).to.equal(maker.address);
    expect(sellOrder.orderType).to.equal(0);
    expect(sellOrder.status).to.equal(false);
  });

  it("should create a buy order", async function () {

    await payToken.connect(taker).deposit({value: ethers.utils.parseEther("5")});
    await expect(wildfire.connect(taker).createBuyOrder(tradeToken.address, buyPrice, buyAmount, {gasLimit : 1000000})).to.emit(wildfire, "OrderCreated").withArgs(1, taker.address, 1);

    const buyOrder = await wildfire.buyOrders(0);
    expect(buyOrder.orderId).to.equal(1);
    expect(buyOrder.token).to.equal(tradeToken.address);
    expect(buyOrder.price).to.equal(buyPrice);
    expect(buyOrder.amount).to.equal(buyAmount);
    expect(buyOrder.creator).to.equal(taker.address);
    expect(buyOrder.orderType).to.equal(1);
    expect(buyOrder.status).to.equal(false);
  });

  it("should cancel a sell order", async function () {

    await tradeToken.mint(maker.address, epochId, sellAmount, {gasLimit : 50000});

    await wildfire.connect(maker).createSellOrder(tradeToken.address, sellPrice, sellAmount, epochId, {gasLimit : 1000000});
    await expect(wildfire.connect(maker).cancelOrder(1, 0)).to.emit(wildfire, "OrderCanceled").withArgs(1, maker.address, 0);

    const sellOrder = await wildfire.sellOrders(0);
    expect(sellOrder.status).to.equal(true);
  });

  it("should cancel a buy order", async function () {

    await payToken.connect(taker).deposit({value: ethers.utils.parseEther("5")});

    await wildfire.connect(taker).createBuyOrder(tradeToken.address, buyPrice, buyAmount);
    await expect(wildfire.connect(taker).cancelOrder(1, 1)).to.emit(wildfire, "OrderCanceled").withArgs(1, taker.address, 1);

    const buyOrder = await wildfire.buyOrders(0);
    expect(buyOrder.status).to.equal(true);
  });

  it("should fulfill a sell order", async function () {
    const sellToken = tradeToken.address;
    const sellPrice = ethers.utils.parseEther("1");
    const sellAmount = 10;
    const epochId = 1;

    const buyPrice = ethers.utils.parseEther("1");
    const buyAmount = 5;

    await tradeToken.mint(maker.address, epochId, sellAmount);
    await payToken.connect(taker).deposit({value: ethers.utils.parseEther("10")});

    await wildfire.connect(maker).createSellOrder(sellToken, sellPrice, sellAmount, epochId);
    await wildfire.connect(taker).createBuyOrder(sellToken, buyPrice, buyAmount);

    const initialSellerBalance = await tradeToken.balanceOf(maker.address, epochId);
    const initialBuyerBalance = await payToken.balanceOf(taker.address);

    await tradeToken.connect(owner).setApprovalForAll(operator.address, true);

    const flag = await tradeToken.isApprovedForAll(operator.address, owner.address);
    console.log("1 -> ",flag)
    await payToken.approve(operator.address, ethers.utils.parseEther("10"));
    console.log("2")

    await expect(wildfire.connect(operator).fullfillOrder(1, 0, 1)).to.emit(wildfire, "OrderFulfilled").withArgs(0, maker.address, taker.address, 1);
    console.log("3")

    const updatedSellerBalance = await tradeToken.balanceOf(maker.address, epochId);
    const updatedBuyerBalance = await payToken.balanceOf(taker.address);



  });

});