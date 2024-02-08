// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TestABONDToken is ERC20, ERC20Burnable, Pausable, Ownable {
    constructor() ERC20("Test ABOND Token", "TABOND") {}

    mapping(address => bool) public whitelist;

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address to, uint256 amount) public returns(bool){
        _mint(to, amount);
        return true;
    }

    function burnFromUser(address to, uint256 amount) public returns(bool){
        burnFrom(to, amount);
        return true;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(from, to, amount);
    }
}