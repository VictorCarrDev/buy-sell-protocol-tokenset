const { toWei, ZERO_ADDRESS } = require("../test/utils");

const SET_CREATOR_ADDRESS = "0x14f0321be5e581abF9d5BC76260bf015Dc04C53d";
const BASIC_ISSUANCE_MODULE = "0x38E5462BBE6A72F79606c1A0007468aA4334A92b";
const TRADE_MODULE = "0xd04AabadEd11e92Fefcd92eEdbBC81b184CdAc82";

const WETH_ADDRESS = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
const WBTC_ADDRESS = "0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6";

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { manager } = await getNamedAccounts();

  const setCreator = await ethers.getContractAt(
    "ISetTokenCreator",
    SET_CREATOR_ADDRESS
  );
  const basicModule = await ethers.getContractAt(
    "IBasicIssuanceModule",
    BASIC_ISSUANCE_MODULE
  );
  const tradeModule = await ethers.getContractAt("ITradeModule", TRADE_MODULE);

  console.log("\nCreating Set Token...");
  const tx = await setCreator.create(
    [WBTC_ADDRESS, WETH_ADDRESS],
    [0.0015e8, toWei("0.03846")], // around $100 per set token
    [BASIC_ISSUANCE_MODULE, TRADE_MODULE],
    manager,
    "ETHBTC Set",
    "ETHBTC"
  );

  const receipt = await tx.wait();

  const setAddress = receipt.events[1].args._setToken;
  console.log("Set Address Deployed At:", setAddress);

  // Initialize Basic Module
  await basicModule.initialize(setAddress, ZERO_ADDRESS);
  console.log("Basic Module Initialized!");

  // Initialize Trade Module
  await tradeModule.initialize(setAddress);
  console.log("Trade Module Initialized!");
};

module.exports.tags = ["SetToken"];
