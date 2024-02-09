// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AMINTStablecoin is ERC20, ERC20Burnable, Pausable, Ownable {
    constructor() ERC20("AMINT TOKEN", "AMINT") {}

    mapping(address => bool) public whitelist;
    address private borrowingContract;
    address private cdsContract;

    modifier onlyBorrowingContract() {
        require(msg.sender == borrowingContract, "This function can only called by borrowing contract");
        _;
    }

    modifier onlyCDSOrBorrowingContract() {
        require((msg.sender == cdsContract) || (msg.sender == borrowingContract), "This function can only called by Borrowing or CDS contract");
        _;
    }

    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyCDSOrBorrowingContract returns(bool){
        _mint(to, amount);
        return true;
    }
    
    function burnFromUser(address to, uint256 amount) public onlyBorrowingContract returns(bool){
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

    function setBorrowingContract(address _address) external onlyOwner {
        require(_address != address(0) && isContract(_address) != false, "Input address is invalid");
        borrowingContract = _address;
    }

    function setCdsContract(address _address) external onlyOwner {
        require(_address != address(0) && isContract(_address) != false, "Input address is invalid");
        cdsContract = _address;
    }
}
