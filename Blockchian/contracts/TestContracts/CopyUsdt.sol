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
import { OFTAdapter } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";
import { TestUSDT } from "../v1Contracts/Copy_UsdtV1.sol";

contract TestUSDTV2 is TestUSDT, Initializable, UUPSUpgradeable, ERC20BurnableUpgradeable, ERC20PausableUpgradeable, OFTAdapter{

    function initialize(      
        address _token,  
        address _lzEndpoint,
        address _delegate
    ) initializer public {
        __OFTAdapter_init(_token,_lzEndpoint,_delegate);
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override{}

    function setDstEid(uint32 _eid) external onlyOwner{
        require(_eid != 0, "EID can't be zero");
        dstEid = _eid;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function decimals() public pure override returns (uint8) {
        return 6;
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

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        super._update(from, to, value);
    }

    function OFTAdapter_init(address _token,address _lzEndpoint,address _delegate) external onlyOwner{
        __OFTAdapter_init(_token,_lzEndpoint,_delegate);
    }
}