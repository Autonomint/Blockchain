// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { State } from "../interface/IAbond.sol";
import "../lib/Colors.sol";
import "hardhat/console.sol";
import { OFT } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";

contract TestABONDToken is Initializable, OFT, UUPSUpgradeable, ERC20BurnableUpgradeable, ERC20PausableUpgradeable{

    mapping(address user => State) public userStates;
    mapping(address user => mapping(uint64 index => State)) public userStatesAtDeposits;
    uint128 PRECISION;
    uint32 private dstEid;

    function initialize(        
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) initializer public {
        __OFT_init(_name, _symbol, _lzEndpoint, _delegate);
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        PRECISION = 1e18;
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override{}

    mapping(address => bool) public whitelist;
    address private borrowingContract;

    modifier onlyBorrowingContract() {
        require(msg.sender == borrowingContract, "This function can only called by borrowing contract");
        _;
    }

    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function setDstEid(uint32 _eid) external {
        require(_eid != 0, "EID can't be zero");
        dstEid = _eid;
    }

    function setBorrowingContract(address _address) external onlyOwner {
        require(_address != address(0) && isContract(_address) != false, "Input address is invalid");
        borrowingContract = _address;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address to, uint64 index, uint256 amount) public onlyBorrowingContract returns(bool){
        require(to != address(0),"Invalid User");
        
        State memory fromState = userStatesAtDeposits[to][index];
        State memory toState = userStates[to];

        fromState.ethBacked = fromState.ethBacked * PRECISION/ uint128(amount);

        toState = Colors._credit(fromState, toState, uint128(amount));

        userStatesAtDeposits[to][index] = fromState;
        userStates[to] = toState;

        _mint(to, amount);
        return true;
    }

    function transfer(address to, uint256 value) public override returns (bool) {

        require(msg.sender != address(0) && to != address(0),"Invalid User");

        State memory fromState = userStates[msg.sender];
        State memory toState = userStates[to];
        
        require(fromState.aBondBalance >= value,"Insufficient aBond balance");
        
        toState = Colors._credit(fromState, toState, uint128(value));
        userStates[to] = toState;

        fromState = Colors._debit(fromState, uint128(value));
        userStates[msg.sender] = fromState;

        super.transfer(to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        require(from != address(0) && to != address(0),"Invalid User");

        State memory fromState = userStates[from];
        State memory toState = userStates[to];

        toState = Colors._credit(fromState, toState, uint128(value));
        userStates[to] = toState;

        Colors._debit(fromState, uint128(value));
        userStates[msg.sender] = fromState;

        super.transferFrom(from, to, value);
        return true;
    }

    function burnFromUser(address to, uint256 amount) public onlyBorrowingContract returns(bool){
        State memory state = userStates[to];
        state = Colors._debit(state, uint128(amount));
        userStates[to] = state; 
        burnFrom(to, amount);
        return true;
    }

    // function _beforeTokenTransfer(address from, address to, uint256 amount)
    //     internal
    //     whenNotPaused
    //     override
    // {
    //     super._beforeTokenTransfer(from, to, amount);
    // }

    function burn(uint256 value) public override onlyBorrowingContract {
        super.burn(value);
    }

    function burnFrom(address account, uint256 value) public override onlyBorrowingContract {
        super.burnFrom(account,value);
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        super._update(from, to, value);
    }

    function setAbondData(address user, uint64 index, uint128 ethBacked, uint128 cumulativeRate) external onlyBorrowingContract{
        
        State memory state = userStatesAtDeposits[user][index];

        state.cumulativeRate = cumulativeRate;
        state.ethBacked = ethBacked;  

        userStatesAtDeposits[user][index] = state;
    }

}
