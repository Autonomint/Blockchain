// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OFT } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";

contract USDaStablecoin is Initializable, OFT, UUPSUpgradeable, ERC20BurnableUpgradeable, ERC20PausableUpgradeable{
    
    mapping(address => bool) private whitelist;
    address private borrowingContract;
    address private cdsContract;
    uint32 private dstEid;

    function initialize(
        address _lzEndpoint,
        address _delegate
    ) initializer public {
        __OFT_init("Autonomint USD", "USDa", _lzEndpoint, _delegate);
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override{}

    modifier onlyCDSOrBorrowingContract() {
        require((msg.sender == cdsContract) || (msg.sender == borrowingContract), "This function can only called by Borrowing or CDS contract");
        _;
    }

    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function setDstEid(uint32 _eid) external onlyOwner{
        require(_eid != 0, "EID can't be zero");
        dstEid = _eid;
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
    
    function burnFromUser(address to, uint256 amount) public onlyCDSOrBorrowingContract returns(bool){
        burnFrom(to, amount);
        return true;
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        super._update(from, to, value);
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