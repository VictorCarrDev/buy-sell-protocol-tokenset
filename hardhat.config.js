/**
 * @type import('hardhat/config').HardhatUserConfig
 */

require("dotenv").config();
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-ethers");
require("hardhat-deploy");
require("@nomiclabs/hardhat-web3");

let mnemonic = process.env.MNEMONIC
  ? process.env.MNEMONIC
  : "test test test test test test test test test test test test";

module.exports = {
  networks: {
    hardhat: {
      // Uncomment these lines to use mainnet fork
      forking: {
        url: `https://polygon-mainnet.g.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`,
        blockNumber: 19433012,
      },
    },
    polygon: {
      url: `https://polygon-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`,
      accounts: {
        mnemonic,
      },
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API,
    // url: "https://api-rinkeby.etherscan.io/",
  },
  namedAccounts: {
    manager: 0,
    dev: 1,
    feeRecipient: 2,
    alice: 3,
    bob: 4,
  },
  solidity: {
    version: "0.8.7",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  mocha: {
    timeout: 240000,
  },
};
