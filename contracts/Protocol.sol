//SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { ISetToken, IBasicIssuanceModule, ISetValuer } from "./interfaces/ITokenSets.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IWETH.sol";
import "./Referral.sol";
import "hardhat/console.sol";

/**
 * @title Protocol.
 */

contract Protocol is Referral {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public setToken;

  // Quickswap Router
  IUniswapV2Router router =
    IUniswapV2Router(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);

  // Wrapped Matic
  IWETH internal constant weth =
    IWETH(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

  address constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;
  address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  address constant USDC_ADDRESS = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

  IBasicIssuanceModule basicModule =
    IBasicIssuanceModule(0x38E5462BBE6A72F79606c1A0007468aA4334A92b);
  ISetValuer setValuer = ISetValuer(0x3700414Bb6716FcD8B14344fb10DDd91FdEA59eC);

  constructor(
    address _setToken,
    uint256[] memory _levelRate,
    uint256[] memory _refereeBonusRateMap
  )
    Referral(
      10000, // decimals
      1000, // 10% of bought tokens (1000/decimals)
      1 days, // seconds until inactive
      false, // onlyRewardActiveReferrers
      _levelRate,
      _refereeBonusRateMap
    )
  {
    setToken = _setToken;
  }

  modifier updateReferrer(uint256 amount, address payable _referrer) {
    if (!hasReferrer(msg.sender)) {
      require(addReferrer(_referrer));
    }
    _;
    // uint price = setValuer.calculateSetTokenValuation(setToken, USDC_ADDRESS);
    // payReferral(amount.mul(price));
    payReferral(amount);
  }

  function isETH(IERC20 token) internal pure returns (bool) {
    return (address(token) == address(ZERO_ADDRESS) ||
      address(token) == address(ETH_ADDRESS));
  }

  function getBalance(IERC20 token, address who)
    internal
    view
    returns (uint256)
  {
    if (isETH(token)) {
      return who.balance;
    } else {
      return token.balanceOf(who);
    }
  }

  function getAmountIn(
    IERC20 fromToken,
    IERC20 destToken,
    uint256 amountOut
  ) public view returns (uint256) {
    address[] memory path = new address[](2);
    path[0] = isETH(fromToken) ? address(weth) : address(fromToken);
    path[1] = isETH(destToken) ? address(weth) : address(destToken);

    uint256[] memory amountsIn = router.getAmountsIn(amountOut, path);

    return amountsIn[0];
  }

  function swap(
    IERC20 fromToken,
    IERC20 destToken,
    uint256 amount
  ) internal {
    uint256 realAmt = amount == type(uint256).max
      ? getBalance(fromToken, address(this))
      : amount;

    IERC20 fromTokenReal = isETH(fromToken) ? weth : fromToken;
    IERC20 toTokenReal = isETH(destToken) ? weth : destToken;

    // console.log("swapping", address(fromToken), address(destToken), amount);

    if (isETH(fromToken)) {
      weth.deposit{ value: realAmt }();
    }

    address[] memory path = new address[](2);
    path[0] = address(fromTokenReal);
    path[1] = address(toTokenReal);

    fromTokenReal.safeApprove(address(router), realAmt);

    router.swapExactTokensForTokens(
      realAmt,
      1,
      path,
      address(this),
      block.timestamp + 1
    );

    if (isETH(destToken)) {
      weth.withdraw(weth.balanceOf(address(this)));
    }
  }

  function buySet(uint256 amount, address payable _referrer)
    public
    updateReferrer(amount, _referrer)
  {
    (
      address[] memory componentAddresses,
      uint256[] memory componentQuantities
    ) = basicModule.getRequiredComponentUnitsForIssue(setToken, amount);

    // Check Allowances to Basic Module
    for (uint256 i = 0; i < componentAddresses.length; i++) {
      require(
        IERC20(componentAddresses[i]).allowance(
          msg.sender,
          address(basicModule)
        ) >= componentQuantities[i]
      );
    }

    // Issue set Tokens
    basicModule.issue(setToken, amount, msg.sender);
  }

  function buySetWithETH(uint256 amount, address payable _referrer)
    public
    payable
    updateReferrer(amount, _referrer)
  {
    require(msg.value > 0, "!MATIC");

    (
      address[] memory componentAddresses,
      uint256[] memory componentQuantities
    ) = basicModule.getRequiredComponentUnitsForIssue(setToken, amount);

    // console.log("Component1", componentAddresses[0]);
    // console.log("Component2", componentAddresses[1]);
    // console.log("Amount1", componentQuantities[0]);
    // console.log("Amount2", componentQuantities[1]);

    // Swap ETH to required component quantities
    for (uint256 i = 0; i < componentAddresses.length; i++) {
      // If already in ETH, only wrap
      if (componentAddresses[i] == address(weth)) {
        weth.deposit{ value: componentQuantities[i] }();
      }
      // If its not ETH address, buy token
      else if (!isETH(IERC20(componentAddresses[i]))) {
        uint256 ethToSwap = getAmountIn(
          IERC20(ETH_ADDRESS),
          IERC20(componentAddresses[i]),
          componentQuantities[i]
        );
        swap(IERC20(ETH_ADDRESS), IERC20(componentAddresses[i]), ethToSwap);
      }

      IERC20(componentAddresses[i]).safeApprove(
        address(basicModule),
        componentQuantities[i]
      );
    }

    // console.log("Balance1", IERC20(componentAddresses[0]).balanceOf(address(this)));
    // console.log("Balance2", IERC20(componentAddresses[1]).balanceOf(address(this)));

    // Issue set Tokens
    basicModule.issue(setToken, amount, msg.sender);
  }
}
