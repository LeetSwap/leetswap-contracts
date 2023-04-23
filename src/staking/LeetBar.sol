// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract LeetBar is ERC20("xLeet", "xLEET") {
    using SafeMath for uint256;
    IERC20 public leet;

    constructor(IERC20 _leet) {
        leet = _leet;
    }

    function enter(uint256 _tokenAmount) public {
        uint256 totalLeet = leet.balanceOf(address(this));
        uint256 totalShares = totalSupply();

        if (totalShares == 0 || totalLeet == 0) {
            _mint(msg.sender, _tokenAmount);
        } else {
            uint256 sharesToMint = _tokenAmount.mul(totalShares).div(totalLeet);
            _mint(msg.sender, sharesToMint);
        }

        leet.transferFrom(msg.sender, address(this), _tokenAmount);
    }

    function leave(uint256 _sharesAmount) public {
        uint256 totalShares = totalSupply();
        uint256 userTokens = _sharesAmount
            .mul(leet.balanceOf(address(this)))
            .div(totalShares);

        _burn(msg.sender, _sharesAmount);
        leet.transfer(msg.sender, userTokens);
    }
}
