require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-etherscan");
require('dotenv').config()


task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

module.exports = {
  defaultNetwork: "hardhat",
  networks: {

    hardhat: {
      forking: {
        url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      }
    },

  },
  etherscan: {
    apiKey: process.env.apiKey 
  },
  solidity: {
    compilers: [
      {
        version: "0.8.19",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
            details: { yul: false }
          }
        },
      },
      {
        version: "0.8.18",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
            details: { yul: false }
          }
        },
      },
      {
        version: "0.8.17",
        settings: {
          optimizer: {
            enabled: true,
            runs: 500,
            details: { yul: false }
          }
        },
      },
    ],
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
        details: { yul: false }
      }
    },

  },

};
