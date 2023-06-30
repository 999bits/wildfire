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

  before(async function () {
    [owner, maker, taker] = await ethers.getSigners();

    const TradeToken = await ethers.getContractFactory("VaultToken");
    tradeToken = await TradeToken.deploy("Vault Token", "Vault Token", "VT");
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
    const sellToken = tradeToken.address;
    const price = ethers.utils.parseEther("0.5");
    const amount = 10;
    const epochId = 1;

    await tradeToken.mint(maker.address, epochId, amount, {gasLimit : 50000});

    await expect(wildfire.connect(maker).createSellOrder(sellToken, price, amount, epochId)).to.emit(wildfire, "OrderCreated").withArgs(1, maker.address, 0);

    const sellOrder = await wildfire.sellOrders(0);
    expect(sellOrder.orderId).to.equal(1);
    expect(sellOrder.token).to.equal(sellToken);
    expect(sellOrder.price).to.equal(price);
    expect(sellOrder.amount).to.equal(amount);
    expect(sellOrder.creator).to.equal(maker.address);
    expect(sellOrder.orderType).to.equal(0);
    expect(sellOrder.status).to.equal(false);
  });

  it("should create a buy order", async function () {
    const buyToken = tradeToken.address;
    const price = ethers.utils.parseEther("0.4");
    const amount = 10;

    await payToken.connect(taker).deposit({value: ethers.utils.parseEther("5")});
    console.log("0")
    const balance = await payToken.balanceOf(taker.address);
    // await payToken.connect(taker).deposit({value : "5"});
    // console.log("taker_balance", await payToken.balanceOf(taker.address));
    console.log("1", balance)
    await expect(wildfire.connect(taker).createBuyOrder(buyToken, price, amount, {gasLimit : 50000})).to.emit(wildfire, "OrderCreated").withArgs(1, taker.address, 1);
    console.log("2")


    
  })

});