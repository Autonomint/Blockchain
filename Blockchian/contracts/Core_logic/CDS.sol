// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interface/ITrinityToken.sol";
import "../interface/IBorrowing.sol";
import "../interface/ITreasury.sol";
import "hardhat/console.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


contract CDS is Ownable{
    // using SafeERC20 for IERC20;

    ITrinityToken public immutable Trinity_token;
    IBorrowing public borrowing;
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
    uint256 public totalAvailableLiquidationAmount;
    uint128 public lastCumulativeRate;
    uint128 public PRECISION = 1e12;

    struct CdsAccountDetails {
        uint64 depositedTime;
        uint128 depositedAmount;
        uint64 withdrawedTime;
        uint128 withdrawedAmount;
        bool withdrawed;
        uint128 depositPrice;
        uint128 depositValue;
        bool optedLiquidation;
        uint128 InitialLiquidationAmount;
        uint128 liquidationAmount;
        uint128 liquidationindex;
        uint128 normalizedAmount;
    }

    struct CdsDetails {
        uint64 index;
        bool hasDeposited;
        mapping ( uint64 => CdsAccountDetails) cdsAccountDetails;
    }

    struct LiquidationInfo{
        uint128 liquidationAmount;
        uint128 profits;
        uint128 ethAmount;
        uint256 availableLiquidationAmount;
    }

    mapping (address => CdsDetails) public cdsDetails;
    mapping (uint128 liquidationIndex => LiquidationInfo) public liquidationIndexToInfo;

    event Deposit(uint128 depositedAmint,uint64 index,uint128 liquidationAmount);
    event Withdraw(uint128 withdrewAmint,uint128 withdrawETH);

    constructor(address _trinity,address priceFeed) {
        Trinity_token = ITrinityToken(_trinity); // _trinity token contract address
        dataFeed = AggregatorV3Interface(priceFeed);
        lastEthPrice = getLatestData();
        lastCumulativeRate = PRECISION;
    }

    modifier onlyBorrowingContract() {
        require( msg.sender == borrowingContract, "This function can only called by borrowing contract");
        _;
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

    function deposit(uint128 _amount,bool _liquidate,uint128 _liquidationAmount) public {
        require(_amount != 0, "Deposit amount should not be zero"); // check _amount not zero
        require(
            _liquidationAmount < _amount,
            "Liquidation amount can't greater than deposited amount"
        );
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
        cdsDetails[msg.sender].cdsAccountDetails[index].normalizedAmount = ((_amount * PRECISION)/lastCumulativeRate);
       
        cdsDetails[msg.sender].cdsAccountDetails[index].depositValue = calculateValue(ethPrice);
        cdsDetails[msg.sender].cdsAccountDetails[index].optedLiquidation = _liquidate;
        if(_liquidate){
            if(borrowing.noOfLiquidations() == 0){
                cdsDetails[msg.sender].cdsAccountDetails[index].liquidationindex = 1;
            }else{
                cdsDetails[msg.sender].cdsAccountDetails[index].liquidationindex = borrowing.noOfLiquidations();
            }
            cdsDetails[msg.sender].cdsAccountDetails[index].liquidationAmount = _liquidationAmount;
            cdsDetails[msg.sender].cdsAccountDetails[index].InitialLiquidationAmount = _liquidationAmount;
            totalAvailableLiquidationAmount += _liquidationAmount;
        }  

        if(ethPrice != lastEthPrice){
            updateLastEthPrice(ethPrice);
        }
       emit Deposit(_amount,index,_liquidationAmount);
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

        uint128 returnAmount = 
            cdsAmountToReturn(msg.sender,_index, ethPrice)+
            ((cdsDetails[msg.sender].cdsAccountDetails[_index].normalizedAmount * lastCumulativeRate)/PRECISION)-(2*(cdsDetails[msg.sender].cdsAccountDetails[_index].depositedAmount));

        cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawedTime =  _withdrawTime;

        if(cdsDetails[msg.sender].cdsAccountDetails[_index].optedLiquidation){

            uint128 currentLiquidations = borrowing.noOfLiquidations();
            uint128 liquidationIndexAtDeposit = cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationindex;
            uint128 ethAmount;

            for(uint128 i = liquidationIndexAtDeposit; i<= currentLiquidations; i++){
                uint128 liquidationAmount = cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount;
                if(liquidationAmount > 0){
                    LiquidationInfo memory liquidationData = liquidationIndexToInfo[i];
                    uint128 share = (liquidationAmount * 1e10)/uint128(liquidationData.availableLiquidationAmount);
                    uint128 profit;
                    profit = (liquidationData.profits * share)/1e10;
                    cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount += profit;
                    cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount -= ((liquidationData.liquidationAmount*share)/1e10);
                    ethAmount += (liquidationData.ethAmount * share)/1e10;
                }
            }
            uint128 returnAmountWithGains = returnAmount + cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount;
            totalCdsDepositedAmount -= returnAmountWithGains;
            cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawedAmount = returnAmountWithGains;
            bool success = Trinity_token.transferFrom(treasuryAddress,msg.sender, returnAmountWithGains); // transfer amount to msg.sender
            require(success == true, "Transsuccessed in cds withdraw");
            treasury.transferEthToCdsLiquidators(msg.sender,ethAmount);
            emit Withdraw(returnAmountWithGains,ethAmount);
        }else{
            // Trinity_token.approve(msg.sender, returnAmount);
            cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawedAmount = returnAmount;
            bool transfer = Trinity_token.transferFrom(treasuryAddress,msg.sender, returnAmount); // transfer amount to msg.sender
            require(transfer == true, "Transfer failed in cds withdraw");
            emit Withdraw(returnAmount,0);
        }

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
        borrowing = IBorrowing(_address);
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

    function calculateCumulativeRate(uint128 fees) public returns(uint128){
        require(fees != 0,"Fees should not be zero");
        uint128 netCDSPoolValue = totalCdsDepositedAmount + fees;
        totalCdsDepositedAmount += fees;
        uint128 percentageChange = (fees * PRECISION)/netCDSPoolValue;
        uint128 currentCumulativeRate;
        if(treasury.noOfBorrowers() == 0){
            currentCumulativeRate = (1 * PRECISION) + percentageChange;
            lastCumulativeRate = currentCumulativeRate;
        }else{
            currentCumulativeRate = lastCumulativeRate * ((1 * PRECISION) + percentageChange);
            lastCumulativeRate = (currentCumulativeRate/PRECISION);
        }
        return currentCumulativeRate;
    }

    function getCDSDepositDetails(address depositor,uint64 index) external view returns(CdsAccountDetails memory){
        return cdsDetails[depositor].cdsAccountDetails[index];
    }

    function updateLiquidationInfo(uint128 index,LiquidationInfo memory liquidationData) external {
        liquidationIndexToInfo[index] = liquidationData;
    }

    function updateTotalAvailableLiquidationAmount(uint256 amount) external onlyBorrowingContract{
        totalAvailableLiquidationAmount -= amount;
    }

    function updateTotalCdsDepositedAmount(uint128 _amount) external{
        totalCdsDepositedAmount += _amount;
    }

    receive() external payable{}
}
