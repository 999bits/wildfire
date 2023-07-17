const { expect } = require("chai");
const { ethers } = require("hardhat");
const { wbnbABI } = require("./abiCode.js");
const { BigNumber } = require("ethers");

//Test wildfire v2 orderbook
describe("WildfireV2", function () {
    let wbnbAddress = "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd";
    let wildfire;
    let tradeToken;
    let payToken;
    let owner;
    let maker;
    let taker;
    let depositAmount = 100;
    let epochId = 1;
    let zeroAddress = "0x0000000000000000000000000000000000000000";
  
    beforeEach(async function () {
      [owner, maker, taker, operator] = await ethers.getSigners();
  
      // Deploy ERC1155 token for tradeToken
      const TradeToken = await ethers.getContractFactory("VaultToken");
      tradeToken = await TradeToken.connect(owner).deploy("Vault Token", "Vault Token", "VT");
      await tradeToken.deployed();
  
      // Deploy WBNB token for payToken
      payToken = await ethers.getContractAt(wbnbABI, wbnbAddress);
      
      // Deploy Wildfire for orderbook
      const Wildfire = await ethers.getContractFactory("WildfireV2");
      wildfire = await Wildfire.deploy(tradeToken.address, payToken.address);
      await wildfire.deployed();

      await tradeToken.mint(maker.address, epochId, depositAmount, {gasLimit : 50000});
      await payToken.connect(taker).deposit({value: ethers.utils.parseEther("50")});

      await tradeToken.connect(maker).setApprovalForAll(wildfire.address, true);
      await payToken.connect(taker).approve(wildfire.address, ethers.utils.parseEther("50"));
    })

    it("SellAmount should be greater than zero to create sell order", async function () {
        let sellPrice = ethers.utils.parseEther("1");
        let sellAmount = 0;   
        await expect(wildfire.connect(maker).createSellOrder(sellPrice, sellAmount, epochId)).to.revertedWith("SellAmount should be greater than zero");
    })
    it("Price should be greater than zero to create sell order", async function () {
        let sellPrice = 0;
        let sellAmount = 10;   
        await expect(wildfire.connect(maker).createSellOrder(sellPrice, sellAmount, epochId)).to.revertedWith("Price should be greater than zero");
    })
    it("BuyAmount should be greater than zero to create buy order", async function () {
        let buyPrice = ethers.utils.parseEther("1");
        let buyAmount = 0;   
        await expect(wildfire.connect(taker).createBuyOrder(buyPrice, buyAmount)).to.revertedWith("BuyAmount should be greater than zero");
    })
    it("Price should be greater than zero to create buy order", async function () {
        let buyPrice = 0;
        let buyAmount = 10;   
        await expect(wildfire.connect(taker).createBuyOrder(buyPrice, buyAmount)).to.revertedWith("Price should be greater than zero");
    })

    it("Maker should not be zero address to fulfill sell order", async function () {
        let sellPrice = ethers.utils.parseEther("1");
        let sellAmount = 10;   
        await expect(wildfire.fulfillSellOrder(zeroAddress, sellPrice, sellAmount, epochId)).to.revertedWith("Maker should not be zero address");
    })
    it("SellAmount should be greater than zero to fulfill sell order", async function () {
        let sellPrice = ethers.utils.parseEther("1");
        let sellAmount = 0;   
        await expect(wildfire.fulfillSellOrder(maker.address, sellPrice, sellAmount, epochId)).to.revertedWith("SellAmount should be greater than zero");
    })
    it("Price should be greater than zero to fulfill sell order", async function () {
        let sellPrice = 0;
        let sellAmount = 10;   
        await expect(wildfire.fulfillSellOrder(maker.address, sellPrice, sellAmount, epochId)).to.revertedWith("Price should be greater than zero");
    })
    it("Maker should not be zero address to fulfill buy order", async function () {
        let buyPrice = ethers.utils.parseEther("1");
        let buyAmount = 10;   
        await expect(wildfire.fulfillBuyOrder(zeroAddress, buyPrice, buyAmount, epochId)).to.revertedWith("Maker should not be zero address");
    })
    it("BuyAmount should be greater than zero to fulfill buy order", async function () {
        let buyPrice = ethers.utils.parseEther("1");
        let buyAmount = 0;   
        await expect(wildfire.fulfillBuyOrder(taker.address, buyPrice, buyAmount, epochId)).to.revertedWith("BuyAmount should be greater than zero");
    })
    it("Price should be greater than zero to fulfill buy order", async function () {
        let buyPrice = 0;
        let buyAmount = 10;   
        await expect(wildfire.fulfillBuyOrder(taker.address, buyPrice, buyAmount, epochId)).to.revertedWith("Price should be greater than zero");
    })

    it("Should maker call sell order cancel function", async function () {
        let sellPrice = ethers.utils.parseEther("1");
        let sellAmount = 10;

        const tx = await wildfire.connect(maker).createSellOrder(sellPrice, sellAmount, epochId);
        const receipt = await tx.wait();
        const event = receipt.events.find((e) => e.event === "OrderCreated")
        const orderId = event.args[0];

        await expect(wildfire.cancelSellOrder(sellPrice, orderId, epochId)).to.revertedWith("Only maker can cancel the order");
    })
    it("Should maker call buy order cancel function", async function () {
        let buyPrice = ethers.utils.parseEther("1");
        let buyAmount = 10; 

        const tx = await wildfire.connect(taker).createBuyOrder(buyPrice, buyAmount);
        const receipt = await tx.wait();
        const event = receipt.events.find((e) => e.event === "OrderCreated")
        const orderId = event.args[0];

        await expect(wildfire.cancelBuyOrder(buyPrice, orderId, epochId)).to.revertedWith("Only maker can cancel the order")
    })


    it ("Fully match a order", async function () {
        let sellPrice = ethers.utils.parseEther("1");
        let sellAmount = 10;
        let buyPrice = ethers.utils.parseEther("1");
        let buyAmount = 10;
        
        await expect(wildfire.connect(maker).createSellOrder(sellPrice, sellAmount, epochId)).to.emit(wildfire, "OrderCreated");
        const sellPriceIndex = String(await wildfire.getIndexOfPrice(sellPrice, 0));

        const priceAmountObj = String(await wildfire.getPriceAmount());
        expect(priceAmountObj).to.be.equal(`${sellPrice},${sellAmount},${sellPrice},0`);

        expect(await wildfire.getDeposits(maker.address, tradeToken.address)).to.equal(sellAmount);
        expect(await wildfire.getDeposits(maker.address, payToken.address)).to.equal(0);

        expect((await wildfire.getAllSellOrders(sellPrice)).length).to.equal(1);
        expect((await wildfire.getAllBuyOrders(sellPrice)).length).to.equal(0);
        
        expect(((await wildfire.orderBook(tradeToken.address, sellPrice))._length).toString()).to.equal('1');
        expect(((await wildfire.orderBook(payToken.address, sellPrice))._length).toString()).to.equal('0');

        await wildfire.fulfillSellOrder(maker.address, sellPrice, sellAmount, epochId);

        await expect(wildfire.connect(taker).createBuyOrder(buyPrice, buyAmount)).to.emit(wildfire, "OrderCreated");
        const buyPriceIndex = String(await wildfire.getIndexOfPrice(buyPrice, 1));
        
        const priceAmountObjAfter = String(await wildfire.getPriceAmount());
        expect(priceAmountObjAfter).to.be.equal(`${sellPrice},${sellAmount},${buyPrice},${buyAmount}`);
        
        expect(await wildfire.getDeposits(taker.address, tradeToken.address)).to.equal(0);
        expect(await wildfire.getDeposits(taker.address, payToken.address)).to.equal(BigNumber.from("10"));

        expect((await wildfire.getAllSellOrders(sellPrice)).length).to.equal(1);
        expect((await wildfire.getAllBuyOrders(buyPrice)).length).to.equal(1);

        expect(((await wildfire.orderBook(tradeToken.address, sellPrice))._length).toString()).to.equal('1');
        expect(((await wildfire.orderBook(payToken.address, buyPrice))._length).toString()).to.equal('1');

        expect(await wildfire.fulfillBuyOrder(taker.address, buyPrice, buyAmount, epochId)).to.emit("OrderFilled"); 

        const tradeBalanceOfMaker = await tradeToken.balanceOf(maker.address, epochId);
        const payBalanceOfMaker = await payToken.balanceOf(maker.address);
        const tradeBalanceOfTaker = await tradeToken.balanceOf(taker.address, epochId);
        const payBalanceOfTaker = await payToken.balanceOf(taker.address);

        expect(((await wildfire.orderBook(tradeToken.address, sellPrice))._length).toString()).to.equal('0');

    })

    it ("Partially match a order", async function () {
        let sellPrice = ethers.utils.parseEther("1");
        let sellAmount = 10;
        let buyPrice = ethers.utils.parseEther("1");
        let buyAmount = 12;
        
        await expect(wildfire.connect(maker).createSellOrder(sellPrice, sellAmount, epochId)).to.emit(wildfire, "OrderCreated");
        const sellPriceIndex = String(await wildfire.getIndexOfPrice(sellPrice, 0));

        const priceAmountObj = String(await wildfire.getPriceAmount());
        expect(priceAmountObj).to.be.equal(`${sellPrice},${sellAmount},${sellPrice},0`);

        expect(await wildfire.getDeposits(maker.address, tradeToken.address)).to.equal(sellAmount);
        expect(await wildfire.getDeposits(maker.address, payToken.address)).to.equal(0);

        expect((await wildfire.getAllSellOrders(sellPrice)).length).to.equal(1);
        expect((await wildfire.getAllBuyOrders(sellPrice)).length).to.equal(0);
        
        expect(((await wildfire.orderBook(tradeToken.address, sellPrice))._length).toString()).to.equal('1');
        expect(((await wildfire.orderBook(payToken.address, sellPrice))._length).toString()).to.equal('0');

        await wildfire.fulfillSellOrder(maker.address, sellPrice, sellAmount, epochId);

        await expect(wildfire.connect(taker).createBuyOrder(buyPrice, buyAmount)).to.emit(wildfire, "OrderCreated");
        const buyPriceIndex = String(await wildfire.getIndexOfPrice(buyPrice, 1));
        
        const priceAmountObjAfter = String(await wildfire.getPriceAmount());
        expect(priceAmountObjAfter).to.be.equal(`${sellPrice},${sellAmount},${buyPrice},${buyAmount}`);
        
        expect(await wildfire.getDeposits(taker.address, tradeToken.address)).to.equal(0);
        expect(await wildfire.getDeposits(taker.address, payToken.address)).to.equal(BigNumber.from("12"));

        expect((await wildfire.getAllSellOrders(sellPrice)).length).to.equal(1);
        expect((await wildfire.getAllBuyOrders(buyPrice)).length).to.equal(1);

        expect(((await wildfire.orderBook(tradeToken.address, sellPrice))._length).toString()).to.equal('1');
        expect(((await wildfire.orderBook(payToken.address, buyPrice))._length).toString()).to.equal('1');

        
        expect(await wildfire.fulfillBuyOrder(taker.address, buyPrice, buyAmount, epochId)).to.emit("OrderPartiallyFilled"); 

        const tradeBalanceOfMaker = await tradeToken.balanceOf(maker.address, epochId);
        const payBalanceOfMaker = await payToken.balanceOf(maker.address);
        const tradeBalanceOfTaker = await tradeToken.balanceOf(taker.address, epochId);
        const payBalanceOfTaker = await payToken.balanceOf(taker.address);

        expect((await wildfire.orderBook(tradeToken.address, sellPrice))._length).to.equal('0');

    })

    it("Cancel sell order", async function () {
        let sellPrice = ethers.utils.parseEther("1");
        let sellAmount = 10;

        const tx = await wildfire.connect(maker).createSellOrder(sellPrice, sellAmount, epochId);
        const receipt = await tx.wait();
        const event = receipt.events.find((e) => e.event === "OrderCreated")
        const orderId = event.args[0];

        await expect(wildfire.connect(maker).cancelSellOrder(sellPrice, orderId, epochId)).to.emit(wildfire, "OrderCancelled");
    })
    it("Cancel buy order", async function () {
        let buyPrice = ethers.utils.parseEther("1");
        let buyAmount = 10; 

        const tx = await wildfire.connect(taker).createBuyOrder(buyPrice, buyAmount);
        const receipt = await tx.wait();
        const event = receipt.events.find((e) => e.event === "OrderCreated")
        const orderId = event.args[0];

        await expect(wildfire.connect(taker).cancelBuyOrder(buyPrice, orderId, epochId)).to.emit(wildfire, "OrderCancelled");
    })
})