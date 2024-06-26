// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.18;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interface/ITrinityToken.sol";
import "hardhat/console.sol";


contract CDS is Ownable{
    // using SafeERC20 for IERC20;

    ITrinityToken public immutable Trinity_token;

    address public borrowingContract;

    uint256 public cdsCount;
    uint96 public withdrawTimeLimit;
    uint128 public totalCdsDepositedAmount;
    uint128 public amountAvailableToBorrow;

    struct CdsAccountDetails {
        uint64 depositedTime;
        uint128 depositedAmount;
        uint64 withdrawedTime;
        uint128 withdrawedAmount;
        bool withdrawed;
    }

    struct CdsDetails {
        uint64 index;
        bool hasDeposited;
        mapping ( uint64 => CdsAccountDetails) cdsAccountDetails;
    }

    mapping (address => CdsDetails) public cdsDetails;

    modifier onlyBorrowContract() {
        require( msg.sender == borrowingContract, "This function can only called by borrowing contract");
        _;

    }

    constructor(address _trinity) {
        Trinity_token = ITrinityToken(_trinity); // _trinity token contract address
    }

    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function deposit(uint128 _amount, uint64 _timeStamp) public {
        require(_amount != 0, "Deposit amount should not be zero"); // check _amount not zero
        require(
            Trinity_token.balanceOf(msg.sender) >= _amount,
            "Insufficient balance with msg.sender"
        ); // check if user has sufficient trinity token

        //Transfer trinity tokens from msg.sender to this contract
        bool transfer = Trinity_token.transferFrom(msg.sender, address(this), _amount); // transfer amount to this contract

        //check it token have successfully transfer or not
        require(transfer == true, "Transfer failed in CDS deposit");

        uint64 index;

        // check if msg.sender is depositing for the first time
        // if yes change hasDeposited from desDeposit structure of msg.sender to true.
        // if not increase index of msg.sender in cdsDetails by 1.
        if (!cdsDetails[msg.sender].hasDeposited) {
            //change hasDeposited to true
            cdsDetails[msg.sender].hasDeposited = true;

            //change index value to 1
            index = cdsDetails[msg.sender].index = 1;

            //Increase cdsCount if msg.sender is depositing for the first time
            ++cdsCount;
        }
        else {
            //increase index value by 1
            index = ++cdsDetails[msg.sender].index;
        }

        //add deposited amount of msg.sender of the perticular index in cdsAccountDetails
        cdsDetails[msg.sender].cdsAccountDetails[index].depositedAmount = _amount;

        //add deposited amount to totalCdsDepositedAmount
        totalCdsDepositedAmount += _amount;

        amountAvailableToBorrow += _amount/2; 

        //amountAvailableToBorrow = totalCdsDepositedAmount/2;
        
        //add deposited time of perticular index and amount in cdsAccountDetails
        cdsDetails[msg.sender].cdsAccountDetails[index].depositedTime = _timeStamp;

    }

    function withdraw(address _to, uint64 _index, uint64 _withdrawTime) public returns(uint256){
       // require(_amount != 0, "Amount cannot be zero");
        require(
            _to != address(0) && isContract(_to) == false,
            "Invalid address"
        );
        require(cdsDetails[msg.sender].index >= _index , "user doesn't have the specified index");
       // require(totalCdsDepositedAmount >= _amount, "Contract doesnt have sufficient balance");
        require(cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawed == false,"Already withdrawn");
        
        if (cdsDetails[msg.sender].cdsAccountDetails[_index].depositedTime + withdrawTimeLimit <= _withdrawTime) {
            revert("cannot withdraw before the withdraw time limit");
        }

        cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawed = true;



        if (cdsDetails[msg.sender].index == 1 && _index == 1) {
            --cdsCount;
        }

        uint128 returnAmount = cdsAmountToReturn(msg.sender,_index);

        totalCdsDepositedAmount -= returnAmount;

        cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawedAmount = returnAmount;
        cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawedTime =  _withdrawTime;
        

        Trinity_token.approve(msg.sender, returnAmount);
    
        bool transfer = Trinity_token.transfer(msg.sender, returnAmount); // transfer amount to msg.sender
        
        require(transfer == true, "Transfer failed in cds withdraw");
    }
   
   function updateAmountAvailabletoBorrow(uint128 _updatedCdsPercentage) external onlyBorrowContract {
        amountAvailableToBorrow = _updatedCdsPercentage;
           
   }

   //calculating Ethereum value to return to CDS owner
   //The function will deduct some amount of ether if it is borrowed
   //Deduced amount will be calculated using the percentage of CDS a user owns
   function cdsAmountToReturn(address _user, uint64 index) internal returns(uint128){
        uint128 safeAmountInCDS = ((cdsDetails[_user].cdsAccountDetails[index].depositedAmount)/2);
        uint128 toReturn = ((cdsDetails[_user].cdsAccountDetails[index].depositedAmount)*amountAvailableToBorrow)/totalCdsDepositedAmount;
        amountAvailableToBorrow -= toReturn;
        return (toReturn + safeAmountInCDS);
   }


    function setWithdrawTimeLimit(uint64 _timeLimit) external onlyOwner {
        require(_timeLimit != 0, "Withdraw time limit can't be zero");
        withdrawTimeLimit = _timeLimit;
    }

    function approval(address _address, uint _amount) external onlyBorrowContract{
        require(_address != address(0) && _amount != 0, "Imput address or amount are invalid");
        bool state = Trinity_token.approve(_address, _amount);
        require(state == true, "Approve failed");
    }

    function setBorrowingContract(address _address) external onlyOwner {
        require(_address != address(0) && isContract(_address) != false, "Input address is invalid");
        borrowingContract = _address;
    }
}