// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interface/ITrinityToken.sol";
import "../interface/ITreasury.sol";
import "hardhat/console.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


contract CDS is Ownable{
    // using SafeERC20 for IERC20;

    ITrinityToken public immutable Trinity_token;
    ITreasury public treasury;
    AggregatorV3Interface internal dataFeed;

    address public borrowingContract;

    address public ethVault;
    address public treasuryAddress;

    uint128 public lastEthPrice;
    uint128 public fallbackEthPrice;
    uint64 public cdsCount;
    uint64 public withdrawTimeLimit;
    uint128 public totalCdsDepositedAmount;

    struct CdsAccountDetails {
        uint64 depositedTime;
        uint128 depositedAmount;
        uint64 withdrawedTime;
        uint128 withdrawedAmount;
        bool withdrawed;
        uint128 depositPrice;
        uint128 depositValue;
    }

    struct CdsDetails {
        uint64 index;
        bool hasDeposited;
        mapping ( uint64 => CdsAccountDetails) cdsAccountDetails;
    }

    mapping (address => CdsDetails) public cdsDetails;

    constructor(address _trinity) {
        Trinity_token = ITrinityToken(_trinity); // _trinity token contract address
        dataFeed = AggregatorV3Interface(
            0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
        );
        lastEthPrice = getLatestData();
    }

    function getLatestData() internal view returns (uint128) {
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        uint temp = uint(answer);
        return uint128(temp);
    }

    function updateLastEthPrice(uint128 priceAtEvent) internal {
        fallbackEthPrice = lastEthPrice;
        lastEthPrice = priceAtEvent;
    }

    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function deposit(uint128 _amount) public {
        require(_amount != 0, "Deposit amount should not be zero"); // check _amount not zero
        require(
            Trinity_token.balanceOf(msg.sender) >= _amount,
            "Insufficient balance with msg.sender"
        ); // check if user has sufficient trinity token

        require(
            Trinity_token.allowance(msg.sender,address(this)) >= _amount,
            "Insufficient allowance"
        ); // check if user has sufficient trinity token allowance



        //Transfer trinity tokens from msg.sender to this contract
        bool transfer = Trinity_token.transferFrom(msg.sender, treasuryAddress, _amount); // transfer amount to this contract

        //check it token have successfully transfer or not
        require(transfer == true, "Transfer failed in CDS deposit");

        uint128 ethPrice = getLatestData();

        require(ethPrice != 0,"Oracle Failed");

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

        //storing current ETH/USD rate
        cdsDetails[msg.sender].cdsAccountDetails[index].depositPrice = ethPrice;

        //add deposited amount to totalCdsDepositedAmount
        totalCdsDepositedAmount += _amount;
        
        //add deposited time of perticular index and amount in cdsAccountDetails
        cdsDetails[msg.sender].cdsAccountDetails[index].depositedTime = uint64(block.timestamp);
        
        cdsDetails[msg.sender].cdsAccountDetails[index].depositValue = calculateValue(ethPrice); 

        if(ethPrice != lastEthPrice){
            updateLastEthPrice(ethPrice);
        }
        
    }

    function withdraw(uint64 _index) public {
       // require(_amount != 0, "Amount cannot be zero");
        // require(
        //     _to != address(0) && isContract(_to) == false,
        //     "Invalid address"
        // );
        require(cdsDetails[msg.sender].index >= _index , "user doesn't have the specified index");
       // require(totalCdsDepositedAmount >= _amount, "Contract doesnt have sufficient balance");
        require(cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawed == false,"Already withdrawn");
        
        uint64 _withdrawTime = uint64(block.timestamp);

        if (cdsDetails[msg.sender].cdsAccountDetails[_index].depositedTime + withdrawTimeLimit <= _withdrawTime) {
            revert("cannot withdraw before the withdraw time limit");
        }

        cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawed = true;

        if (cdsDetails[msg.sender].index == 1 && _index == 1) {
            --cdsCount;
        }

        uint128 ethPrice = getLatestData();
        require(ethPrice != 0,"Oracle Failed");

        uint128 returnAmount = cdsAmountToReturn(msg.sender,_index, ethPrice);

        totalCdsDepositedAmount -= returnAmount;

        cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawedAmount = returnAmount;
        cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawedTime =  _withdrawTime;

        // Trinity_token.approve(msg.sender, returnAmount);
    
        bool transfer = Trinity_token.transferFrom(treasuryAddress,msg.sender, returnAmount); // transfer amount to msg.sender
        
        require(transfer == true, "Transfer failed in cds withdraw");

        if(ethPrice != lastEthPrice){
            updateLastEthPrice(ethPrice);
        }

    }
   

   //calculating Ethereum value to return to CDS owner
   //The function will deduct some amount of ether if it is borrowed
   //Deduced amount will be calculated using the percentage of CDS a user owns
   function cdsAmountToReturn(address _user, uint64 index, uint128 _ethPrice) internal view returns(uint128){
        

        uint128 withdrawalVal = calculateValue(_ethPrice);
        uint128 depositVal = cdsDetails[msg.sender].cdsAccountDetails[index].depositValue;

        if(withdrawalVal <= depositVal){
            uint128 valDiff = depositVal - withdrawalVal;

            uint128 safeAmountInCDS = cdsDetails[_user].cdsAccountDetails[index].depositedAmount;
            uint128 loss = (safeAmountInCDS * valDiff) / 1000;

            return (safeAmountInCDS - loss);
        }

        else{
            uint128 valDiff = withdrawalVal - depositVal;

            uint128 safeAmountInCDS = cdsDetails[_user].cdsAccountDetails[index].depositedAmount;
            uint128 toReturn = (safeAmountInCDS * valDiff) / 1000;

            return (toReturn + safeAmountInCDS);
        }
        
   }


    function setWithdrawTimeLimit(uint64 _timeLimit) external onlyOwner {
        require(_timeLimit != 0, "Withdraw time limit can't be zero");
        withdrawTimeLimit = _timeLimit;
    }

    function approval(address _address, uint _amount) external onlyOwner{
        treasury.approval(_address,_amount);
    }

    function setBorrowingContract(address _address) external onlyOwner {
        require(_address != address(0) && isContract(_address) != false, "Input address is invalid");
        borrowingContract = _address;
    }

    function setTreasury(address _treasury) external onlyOwner{
        require(_treasury != address(0) && isContract(_treasury) != false, "Input address is invalid");
        treasuryAddress = _treasury;
        treasury = ITreasury(_treasury);
    }

    function calculateValue(uint128 _price) internal view returns(uint128) {
        uint128 _amount = 1000;
        uint128 treasuryBal = uint128(Trinity_token.balanceOf(treasuryAddress));
        uint128 vaultBal = uint128(address(this).balance);
        uint128 priceDiff;

        if(_price != lastEthPrice){
            priceDiff = _price - lastEthPrice;
        }

        else{
            priceDiff = _price - fallbackEthPrice;
        }
        uint128 value = (_amount * vaultBal * priceDiff) / treasuryBal;
        return value;
    }

    receive() external payable{}
}
