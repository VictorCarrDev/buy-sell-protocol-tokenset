//SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { ISetToken, IBasicIssuanceModule } from "./interfaces/ITokenSets.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router.sol";
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
  IUniswapV2Router02 router =
    IUniswapV2Router02(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);

  // Wrapped Matic
  IWETH internal constant weth =
    IWETH(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

  address constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;
  address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  IBasicIssuanceModule basicModule =
    IBasicIssuanceModule(0x38E5462BBE6A72F79606c1A0007468aA4334A92b);

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
    uint256 amount,
    uint256 neededAmountOut
  ) internal {
    uint256 realAmt = amount == type(uint256).max
      ? getBalance(fromToken, address(this))
      : amount;

    IERC20 fromTokenReal = isETH(fromToken) ? weth : fromToken;

    require(msg.value >= realAmt, "not enough tokens to swap");
    require(!isETH(destToken), "Destiny token should not be ETH");
    if (isETH(fromToken)) {
      weth.deposit{ value: realAmt }();
    }

    address[] memory path = new address[](2);
    path[0] = address(fromTokenReal);
    path[1] = address(destToken);

    console.log(realAmt , 'begore errir');
    fromTokenReal.approve(address(router), (realAmt * 105) / 100);

    router.swapTokensForExactTokens(
      neededAmountOut,
      (realAmt * 105) / 100,
      path,
      address(this),
      block.timestamp + 5
    );
  }

  function swapTokenToETH(IERC20 fromToken, uint256 amount) internal {
    uint256 realAmt = amount == type(uint256).max
      ? getBalance(fromToken, address(this))
      : amount;

    IERC20 fromTokenReal = isETH(fromToken) ? weth : fromToken;
    IWETH toTokenReal = weth;

    if (isETH(fromToken)) {
      weth.deposit{ value: realAmt }();
    }

    address[] memory path = new address[](2);
    path[0] = address(fromTokenReal);
    path[1] = address(toTokenReal);

    if (fromToken == weth) {
      weth.withdraw(weth.balanceOf(address(this)));
    } else {
      console.log('this is the moneyy, well the address', realAmt,address(fromToken));
      fromToken.approve(address(router), realAmt);
      router.swapExactTokensForTokens(
        realAmt,
        1,
        path,
        address(this),
        block.timestamp + 1
      );
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
        // console.log(ethToSwap, "this is the amount");
        swap(
          IERC20(ETH_ADDRESS),
          IERC20(componentAddresses[i]),
          ethToSwap,
          componentQuantities[i]
        );
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
    payable(msg.sender).transfer(address(this).balance);
  }

  function costSetWithETH(uint256 amount) external view returns (uint256) {
    (
      address[] memory componentAddresses,
      uint256[] memory componentQuantities
    ) = basicModule.getRequiredComponentUnitsForIssue(setToken, amount);

    uint256 totalOut = 0;

    // Swap ETH to required component quantities
    for (uint256 i = 0; i < componentAddresses.length; i++) {
      // If already in ETH, only wrap
      if (componentAddresses[i] == address(weth)) {
        totalOut += componentQuantities[i];
      }
      // If its not ETH address, buy token
      else if (!isETH(IERC20(componentAddresses[i]))) {
        uint256 ethToSwap = getAmountIn(
          IERC20(ETH_ADDRESS),
          IERC20(componentAddresses[i]),
          componentQuantities[i]
        );
        console.log(ethToSwap, "this is the amount");
        totalOut += ethToSwap;
      }
    }

    totalOut = (totalOut * 105) / 100;

    return totalOut;
  }

  function SellSetForETH(uint256 amount) external returns (uint256) {

    console.log(IERC20(setToken).allowance(msg.sender, address(this)), 'this is the allowance');

    require(amount <= IERC20(setToken).allowance(msg.sender, address(this)), 
    'not aproved to sell');

    IERC20(setToken).transferFrom(msg.sender, address(this), amount);
    basicModule.redeem(setToken, amount, address(this));


    (
      address[] memory componentAddresses,
      uint256[] memory componentQuantities
    ) = basicModule.getRequiredComponentUnitsForIssue(setToken, amount);


    // Swap ETH to required component quantities
    for (uint256 i = 0; i < componentAddresses.length; i++) {
      
      swapTokenToETH(IERC20(componentAddresses[i]),componentQuantities[i]);
    }

    uint toReturn = address(this).balance;
    payable(msg.sender).transfer(toReturn);

    return toReturn;

  }

  receive() payable external {}


}
