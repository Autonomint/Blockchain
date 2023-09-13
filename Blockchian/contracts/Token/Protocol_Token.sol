// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ProtocolToken is ERC20, ERC20Burnable, Pausable, Ownable {
    constructor() ERC20("ProtocolToken", "PT") {}

    mapping(address => bool) public whitelist;

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
