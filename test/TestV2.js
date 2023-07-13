const { expect } = require("chai");
const { ethers } = require("hardhat");
const { wbnbABI } = require("./abiCode.js");

describe("WildfireV2", function () {
    let wbnbAddress = "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd";
    let wildfire;
    let tradeToken;
    let payToken;
    let owner;
    let maker;
    let taker;
    let sellPrice = ethers.utils.parseEther("0.1");
    let sellAmount = 10;
    let buyPrice = ethers.utils.parseEther("0.1");
    let buyAmount = 10;
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

    it ("Fully match a sell order", async function () {
        
        await expect(wildfire.connect(maker).createSellOrder(sellPrice, sellAmount, epochId)).to.emit(wildfire, "OrderCreated");
        const priceIndex = String(await wildfire.getIndexOfPrice(sellPrice, 0));
        console.log("priceIndex", priceIndex)

        const priceAmountObj = String(await wildfire.getPriceAmount());
        console.log(priceAmountObj)
        expect(priceAmountObj).to.be.equal(`${sellPrice},${sellAmount},${sellPrice},0`)
    })

})