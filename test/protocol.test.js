const chai = require("chai");
const {
  getNamedAccounts,
  deployments: { fixture },
  ethers,
} = require("hardhat");
const { solidity } = require("ethereum-waffle");
const { expect } = chai;
chai.use(solidity);
const { fromWei, toWei, ZERO_ADDRESS } = require("../test/utils");

// Addresses
const SET_CREATOR_ADDRESS = "0x14f0321be5e581abF9d5BC76260bf015Dc04C53d";
const BASIC_ISSUANCE_MODULE = "0x38E5462BBE6A72F79606c1A0007468aA4334A92b";
const TRADE_MODULE = "0xd04AabadEd11e92Fefcd92eEdbBC81b184CdAc82";

const WETH_ADDRESS = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
const WBTC_ADDRESS = "0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6";
const USDC_ADDRESS = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";

// Contract params
const LEVEL_RATE = [1000, 500]; //  Level 1 - 10%, Level 2 - 5%
const BONUS_RATE_MAP = [1, 10000]; //  100%

describe("Set Protocol", () => {
  before(async function () {
    ({ manager, alice, bob } = await getNamedAccounts());
    aliceSigner = await ethers.provider.getSigner(alice);
    bobSigner = await ethers.provider.getSigner(bob);

    setCreator = await ethers.getContractAt(
      "ISetTokenCreator",
      SET_CREATOR_ADDRESS
    );
    basicModule = await ethers.getContractAt(
      "IBasicIssuanceModule",
      BASIC_ISSUANCE_MODULE
    );
    tradeModule = await ethers.getContractAt("ITradeModule", TRADE_MODULE);

    wbtc = await ethers.getContractAt("IERC20", WBTC_ADDRESS);
    weth = await ethers.getContractAt("IERC20", WETH_ADDRESS);
    usdc = await ethers.getContractAt("IERC20", USDC_ADDRESS);

    console.log("\nCreating Set Token...");
    const tx = await setCreator.create(
      [WBTC_ADDRESS, WETH_ADDRESS],
      [0.000227e8, toWei("0.00315")], // around $20 per set token
      [BASIC_ISSUANCE_MODULE, TRADE_MODULE],
      manager,
      "ETHBTC Set",
      "ETHBTC"
    );
    const receipt = await tx.wait();

    setAddress = receipt.events[1].args._setToken;
    console.log("Set Address Deployed At:", setAddress);
    setToken = await ethers.getContractAt("ISetToken", setAddress);

    // Initialize Basic Module
    await basicModule.initialize(setAddress, ZERO_ADDRESS);
    console.log("Basic Module Initialized!");

    // Initialize Trade Module
    await tradeModule.initialize(setAddress);
    console.log("Trade Module Initialized!");
  });

  it("should deploy protocol contract", async function () {
    Protocol = await ethers.getContractFactory("Protocol");
    protocol = await Protocol.deploy(setAddress, LEVEL_RATE, BONUS_RATE_MAP);
  });

  it("should buy 1 set Token using ETH", async function () {
    
    const trans = await protocol.connect(aliceSigner).buySetWithETH(toWei(1), bob, {
      value: toWei(60),
    });
    
    console.log((await ethers.provider.getBalance(protocol.address)).toString() , 'balance of protocol ')

    

    // console.log(trans)

    const balance = await setToken.balanceOf(alice);
    expect(fromWei(balance)).equal(1);
  });

  it("should get correct referree rewards", async function () {
    const { referrer, reward, referredCount } = await protocol.accounts(alice);
    expect(referrer).equal(bob);
    expect(reward).equal(0);
    expect(referredCount).equal(0);
  });

  it("should get correct referrer rewards", async function () {
    const { referrer, reward, referredCount } = await protocol.accounts(bob);
    expect(referrer).equal(ZERO_ADDRESS);
    expect(fromWei(reward)).equal(0.01); // 1% of 1 token
    expect(referredCount).equal(1);
  });
});
