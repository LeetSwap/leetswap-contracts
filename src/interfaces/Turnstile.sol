// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

interface Turnstile {
    function register(address recipient)
        external
        returns (uint256 beneficiaryTokenID);

    function assign(uint256 beneficiaryTokenID)
        external
        returns (uint256 beneficiaryTokenID_);

    function withdraw(
        uint256 tokenId,
        address payable recipient,
        uint256 amount
    ) external returns (uint256 amount_);

    function balances(uint256 tokenId) external view returns (uint256 amount);
}
