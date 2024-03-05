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

contract TestABONDToken is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, ERC20PausableUpgradeable, UUPSUpgradeable, OwnableUpgradeable {

    mapping(address user => State) public userStates;
    mapping(address user => mapping(uint64 index => State)) public userStatesAtDeposits;

    function initialize() initializer public {
        __ERC20_init("Test ABOND Token", "TABOND");
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override{}

    mapping(address => bool) public whitelist;
    address private borrowingContract;

    modifier onlyBorrowingContract() {
        require(msg.sender == borrowingContract, "This function can only called by borrowing contract");
        _;
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

    function mint(address to, uint64 index, uint256 amount) public returns(bool){
        require(to == address(0),"Invalid User");
        
        State memory fromState = userStatesAtDeposits[to][index];
        State memory toState = userStates[to];
        toState = Colors._credit(fromState, toState, uint64(amount));
        toState.aBondBalance += uint64(amount); 
        userStates[to] = toState;

        _mint(to, amount);
        return true;
    }

    function transfer(address to, uint256 value) public override returns (bool) {

        require(msg.sender == address(0) && to == address(0),"Invalid User");

        State memory fromState = userStates[msg.sender];
        State memory toState = userStates[to];
        
        require(fromState.aBondBalance >= value,"Insufficient aBond balance");
        
        toState = Colors._credit(fromState, toState, uint64(value));
        userStates[to] = toState;

        fromState = Colors._debit(fromState, uint64(value));
        userStates[msg.sender] = fromState;

        super.transfer(to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        require(from == address(0) && to == address(0),"Invalid User");

        State memory fromState = userStates[from];
        State memory toState = userStates[to];

        toState = Colors._credit(fromState, toState, uint64(value));
        userStates[to] = toState;

        Colors._debit(fromState, uint64(value));
        userStates[msg.sender] = fromState;

        super.transferFrom(from, to, value);
        return true;
    }

    function burnFromUser(address to, uint256 amount) public onlyBorrowingContract returns(bool){
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
