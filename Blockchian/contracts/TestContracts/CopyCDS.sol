// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interface/IAmint.sol";
import "../interface/IBorrowing.sol";
import "../interface/ITreasury.sol";
import "../interface/IMultiSign.sol";
import "hardhat/console.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract CDSTest is Initializable,OwnableUpgradeable,UUPSUpgradeable,ReentrancyGuardUpgradeable{

    IAMINT      public amint; // our stablecoin
    IBorrowing  public borrowing; // Borrowing contract interface
    ITreasury   public treasury; // Treasury contrcat interface
    AggregatorV3Interface internal dataFeed;
    IMultiSign  public multiSign;
    IERC20      public usdt; // USDT interface

    address private admin; // admin address
    address public borrowingContract; // borrowing contract address
    address public treasuryAddress; // treasury contract address

    uint128 public lastEthPrice;
    uint128 public fallbackEthPrice;
    uint64  public cdsCount; // cds depositors count
    uint64  public withdrawTimeLimit; // Fixed Time interval between deposit and withdraw
    uint256 public totalCdsDepositedAmount; // total amint and usdt deposited in cds
    uint256 public totalCdsDepositedAmountWithOptionFees;
    uint256 public totalAvailableLiquidationAmount; // total deposited amint available for liquidation
    uint128 public lastCumulativeRate; 
    uint8   public amintLimit; // amint limit in percent
    uint64  public usdtLimit; // usdt limit in number
    uint256 public usdtAmountDepositedTillNow; // total usdt deposited till now
    uint256 public burnedAmintInRedeem;
    uint128 public cumulativeValue;
    bool    public cumulativeValueSign;
    uint128 public PRECISION;
    uint128 RATIO_PRECISION;

    struct CdsAccountDetails {
        uint64 depositedTime;
        uint256 depositedAmount;
        uint64 withdrawedTime;
        uint256 withdrawedAmount;
        bool withdrawed;
        uint128 depositPrice;
        uint128 depositValue;
        bool depositValueSign;
        bool optedLiquidation;
        uint128 InitialLiquidationAmount;
        uint128 liquidationAmount;
        uint128 liquidationindex;
        uint256 normalizedAmount;
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
    
    struct CalculateValueResult{
        uint128 currentValue;
        bool gains;
    }

    mapping (address => CdsDetails) public cdsDetails;

    // liquidations info based on liquidation numbers
    mapping (uint128 liquidationIndex => LiquidationInfo) public liquidationIndexToInfo;

    event Deposit(uint256 depositedAmint,uint64 index,uint128 liquidationAmount,uint256 normalizedAmount,uint128 depositVal);
    event Withdraw(uint256 withdrewAmint,uint128 withdrawETH);

    // constructor(address _amint,address priceFeed,address _usdt,address _multiSign) Ownable(msg.sender) {
    //     amint = IAMINT(_amint); // amint token contract address
    //     usdt = IERC20(_usdt);
    //     multiSign = IMultiSign(_multiSign);
    //     dataFeed = AggregatorV3Interface(priceFeed);
    //     lastEthPrice = getLatestData();
    //     fallbackEthPrice = lastEthPrice;
    //     lastCumulativeRate = PRECISION;
    //     cumulativeValueSign = true;
    // }

    function initialize(
        address _amint,
        address priceFeed,
        address _usdt,
        address _multiSign
    ) initializer public{
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        amint = IAMINT(_amint); // amint token contract address
        usdt = IERC20(_usdt);
        multiSign = IMultiSign(_multiSign);
        dataFeed = AggregatorV3Interface(priceFeed);
        lastEthPrice = getLatestData();
        fallbackEthPrice = lastEthPrice;
        PRECISION = 1e12;
        RATIO_PRECISION = 1e4;
        lastCumulativeRate = PRECISION;
        cumulativeValueSign = true;
    }

    function _authorizeUpgrade(address implementation) internal onlyOwner override{}

    modifier onlyAdmin(){
        require(msg.sender == admin,"Caller is not an admin");
        _;
    }

    modifier onlyBorrowingContract() {
        require( msg.sender == borrowingContract, "This function can only called by borrowing contract");
        _;
    }

    modifier whenNotPaused(IMultiSign.Functions _function) {
        require(!multiSign.functionState(_function),'Paused');
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
        return uint128(temp/1e6);
    }

    function updateLastEthPrice(uint128 priceAtEvent) internal {
        fallbackEthPrice = lastEthPrice;
        lastEthPrice = priceAtEvent;
    }

    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    /**
     * @dev set admin address
     * @param _admin  admin address
     */
    function setAdmin(address _admin) external onlyOwner{
        require(_admin != address(0) && isContract(_admin) != true, "Admin can't be contract address & zero address");
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(5)));
        admin = _admin;    
    }

    /**
     * @dev amint and usdt deposit to cds
     * @param usdtAmount usdt amount to deposit
     * @param amintAmount amint amount to deposit
     * @param _liquidate whether the user opted for liquidation
     * @param _liquidationAmount If opted for liquidation,the liquidation amount
     */
    function deposit(
        uint128 usdtAmount,
        uint128 amintAmount,
        bool _liquidate,
        uint128 _liquidationAmount,
        uint128 ethPrice
    ) public nonReentrant whenNotPaused(IMultiSign.Functions(4)){
        // totalDepositingAmount is usdt and amint
        uint256 totalDepositingAmount = usdtAmount + amintAmount;
        require(totalDepositingAmount != 0, "Deposit amount should not be zero"); // check _amount not zero
        require(
            _liquidationAmount <= (totalDepositingAmount),
            "Liquidation amount can't greater than deposited amount"
        );

        if((usdtAmountDepositedTillNow + usdtAmount) <= usdtLimit){
            require(usdtAmount == totalDepositingAmount,'100% of amount must be USDT');
        }else{
            require(amintAmount >= (amintLimit * totalDepositingAmount)/100,"Required AMINT amount not met");
            require(amint.balanceOf(msg.sender) >= amintAmount,"Insufficient AMINT balance with msg.sender"); // check if user has sufficient AMINT token
        }

        // uint128 ethPrice = getLatestData();

        // require(ethPrice != 0,"Oracle Failed");

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
        cdsDetails[msg.sender].cdsAccountDetails[index].depositedAmount = totalDepositingAmount;

        //storing current ETH/USD rate
        cdsDetails[msg.sender].cdsAccountDetails[index].depositPrice = ethPrice;
        CalculateValueResult memory result = calculateValue(ethPrice);
        setCumulativeValue(result.currentValue,result.gains);
        cdsDetails[msg.sender].cdsAccountDetails[index].depositValue = cumulativeValue;
        cdsDetails[msg.sender].cdsAccountDetails[index].depositValueSign = cumulativeValueSign;

        //add deposited amount to totalCdsDepositedAmount
        totalCdsDepositedAmount += totalDepositingAmount;
        totalCdsDepositedAmountWithOptionFees += totalDepositingAmount;
        //increment usdtAmountDepositedTillNow
        usdtAmountDepositedTillNow += usdtAmount;
        
        //add deposited time of perticular index and amount in cdsAccountDetails
        cdsDetails[msg.sender].cdsAccountDetails[index].depositedTime = uint64(block.timestamp);
        cdsDetails[msg.sender].cdsAccountDetails[index].normalizedAmount = ((totalDepositingAmount * PRECISION)/lastCumulativeRate);
       
        cdsDetails[msg.sender].cdsAccountDetails[index].optedLiquidation = _liquidate;
        //If user opted for liquidation
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

        if(usdtAmount != 0 && amintAmount != 0){
            require(usdt.balanceOf(msg.sender) >= usdtAmount,"Insufficient USDT balance with msg.sender"); // check if user has sufficient AMINT token
            bool usdtTransfer = usdt.transferFrom(msg.sender, treasuryAddress, usdtAmount); // transfer amount to this contract
            require(usdtTransfer == true, "USDT Transfer failed in CDS deposit");
            //Transfer AMINT tokens from msg.sender to this contract
            bool amintTransfer = amint.transferFrom(msg.sender, treasuryAddress, amintAmount); // transfer amount to this contract       
            require(amintTransfer == true, "AMINT Transfer failed in CDS deposit");
        }else if(usdtAmount == 0){
            bool transfer = amint.transferFrom(msg.sender, treasuryAddress, amintAmount); // transfer amount to this contract
            //check it token have successfully transfer or not
            require(transfer == true, "AMINT Transfer failed in CDS deposit");
        }else{
            require(usdt.balanceOf(msg.sender) >= usdtAmount,"Insufficient USDT balance with msg.sender"); // check if user has sufficient AMINT token
            bool transfer = usdt.transferFrom(msg.sender, treasuryAddress, usdtAmount); // transfer amount to this contract
            //check it token have successfully transfer or not
            require(transfer == true, "USDT Transfer failed in CDS deposit");
        }

        if(usdtAmount != 0 ){
            bool success = amint.mint(treasuryAddress,usdtAmount);
            require(success == true, "AMINT mint to treasury failed in CDS deposit");
        }

        emit Deposit(totalDepositingAmount,index,_liquidationAmount,cdsDetails[msg.sender].cdsAccountDetails[index].normalizedAmount,cdsDetails[msg.sender].cdsAccountDetails[index].depositValue);
    }

    /**
     * @dev withdraw amint
     * @param _index index of the deposit to withdraw
     */
    function withdraw(uint64 _index,uint128 ethPrice) public nonReentrant whenNotPaused(IMultiSign.Functions(5)){
        require(cdsDetails[msg.sender].index >= _index , "user doesn't have the specified index");
        require(cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawed == false,"Already withdrawn");
        
        uint64 _withdrawTime = uint64(block.timestamp);

        require(cdsDetails[msg.sender].cdsAccountDetails[_index].depositedTime + withdrawTimeLimit <= _withdrawTime,"cannot withdraw before the withdraw time limit");

        cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawed = true;

        if (cdsDetails[msg.sender].index == 1 && _index == 1) {
            --cdsCount;
        }

        // uint128 ethPrice = getLatestData();
        // require(ethPrice != 0,"Oracle Failed");
        // Calculate return amount includes
        // eth Price difference gain or loss
        // option fees
        uint256 returnAmount = 
            cdsAmountToReturn(msg.sender,_index, ethPrice)+
            ((cdsDetails[msg.sender].cdsAccountDetails[_index].normalizedAmount * lastCumulativeRate)/PRECISION)-(cdsDetails[msg.sender].cdsAccountDetails[_index].depositedAmount);
        cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawedAmount = returnAmount;
        cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawedTime =  _withdrawTime;

        // If user opted for liquidation
        if(cdsDetails[msg.sender].cdsAccountDetails[_index].optedLiquidation){
            returnAmount -= cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount;
            uint128 currentLiquidations = borrowing.noOfLiquidations();
            uint128 liquidationIndexAtDeposit = cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationindex;
            uint128 ethAmount;
        // Loop through the liquidations that were done after user enters
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
            uint256 returnAmountWithGains = returnAmount + cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount;
            totalCdsDepositedAmount -= cdsDetails[msg.sender].cdsAccountDetails[_index].depositedAmount;
            totalCdsDepositedAmountWithOptionFees -= returnAmountWithGains;
            cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawedAmount = returnAmountWithGains;
            // Get approval from treasury 
            treasury.approveAmint(address(this),returnAmountWithGains);

            //Call transferFrom in amint
            bool success = amint.transferFrom(treasuryAddress,msg.sender, returnAmountWithGains); // transfer amount to msg.sender
            require(success == true, "Transsuccessed in cds withdraw");
            
            if(ethAmount != 0){
                treasury.updateEthProfitsOfLiquidators(ethAmount,false);
                // Call transferEthToCdsLiquidators to tranfer eth
                treasury.transferEthToCdsLiquidators(msg.sender,ethAmount);
            }

            emit Withdraw(returnAmountWithGains,ethAmount);
        }else{
            // amint.approve(msg.sender, returnAmount);
            totalCdsDepositedAmount -= cdsDetails[msg.sender].cdsAccountDetails[_index].depositedAmount;
            totalCdsDepositedAmountWithOptionFees -= returnAmount;
            cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawedAmount = returnAmount;
            if(treasury.totalVolumeOfBorrowersAmountinUSD() != 0){
                require(borrowing.calculateRatio(0,ethPrice) > (2 * RATIO_PRECISION),"Not enough fund in CDS");
            }
            treasury.approveAmint(address(this),returnAmount);
            bool transfer = amint.transferFrom(treasuryAddress,msg.sender, returnAmount); // transfer amount to msg.sender
            require(transfer == true, "Transfer failed in cds withdraw");
        }

        if(ethPrice != lastEthPrice){
            updateLastEthPrice(ethPrice);
        }
        emit Withdraw(returnAmount,0);
    }
   

    //calculating Ethereum value to return to CDS owner
    //The function will deduct some amount of ether if it is borrowed
    //Deduced amount will be calculated using the percentage of CDS a user owns
    function cdsAmountToReturn(
        address _user,
        uint64 index,
        uint128 _ethPrice
    ) internal returns(uint256){

        // Calculate current value
        CalculateValueResult memory result = calculateValue(_ethPrice);
        setCumulativeValue(result.currentValue,result.gains);
        uint256 depositedAmount = cdsDetails[_user].cdsAccountDetails[index].depositedAmount;
        uint128 cumulativeValueAtDeposit = cdsDetails[msg.sender].cdsAccountDetails[index].depositValue;
        // Get the cumulative value sign at the time of deposit
        bool cumulativeValueSignAtDeposit = cdsDetails[msg.sender].cdsAccountDetails[index].depositValueSign;
        uint128 valDiff;
        uint128 cumulativeValueAtWithdraw = cumulativeValue;

        // If the depositVal and cumulativeValue both are in same sign
        if(cumulativeValueSignAtDeposit == cumulativeValueSign){
            if(cumulativeValueAtDeposit > cumulativeValueAtWithdraw){
                valDiff = cumulativeValueAtDeposit - cumulativeValueAtWithdraw;
            }else{
                valDiff = cumulativeValueAtWithdraw - cumulativeValueAtDeposit;
            }
            // If cumulative value sign at the time of deposit is positive
            if(cumulativeValueSignAtDeposit){
                if(cumulativeValueAtDeposit > cumulativeValueAtWithdraw){
                    // Its loss since cumulative val is low
                    uint256 loss = (depositedAmount * valDiff) / 1e11;
                    return (depositedAmount - loss);
                }else{
                    // Its gain since cumulative val is high
                    uint256 profit = (depositedAmount * valDiff)/1e11;
                    return (depositedAmount + profit);
                }
            }else{
                if(cumulativeValueAtDeposit > cumulativeValueAtWithdraw){
                    uint256 profit = (depositedAmount * valDiff)/1e11;
                    return (depositedAmount + profit);
                }else{
                    uint256 loss = (depositedAmount * valDiff) / 1e11;
                    return (depositedAmount - loss);
                }
            }
        }else{
            valDiff = cumulativeValueAtDeposit + cumulativeValueAtWithdraw;
            if(cumulativeValueSignAtDeposit){
                uint256 loss = (depositedAmount * valDiff) / 1e11;
                return (depositedAmount - loss);
            }else{
                uint256 profit = (depositedAmount * valDiff)/1e11;
                return (depositedAmount + profit);            
            }
        }
   }

    /**
     * @dev acts as dex amint to usdt
     * @param _amintAmount amint amount to deposit
     * @param amintPrice amint price
     * @param usdtPrice usdt price
     */
    function redeemUSDT(
        uint128 _amintAmount,
        uint64 amintPrice,
        uint64 usdtPrice
    ) public nonReentrant whenNotPaused(IMultiSign.Functions(6)){
        require(_amintAmount != 0,"Amount should not be zero");

        require(amint.balanceOf(msg.sender) >= _amintAmount,"Insufficient balance");
        burnedAmintInRedeem += _amintAmount;
        bool transfer = amint.burnFromUser(msg.sender,_amintAmount);
        require(transfer == true, "AMINT Burn failed in redeemUSDT");

        uint128 _usdtAmount = (amintPrice * _amintAmount/usdtPrice);  
          
        treasury.approveUsdt(address(this),_usdtAmount);
        bool success = usdt.transferFrom(treasuryAddress,msg.sender,_usdtAmount);
        require(success == true, "USDT Transfer failed in redeemUSDT");
    }

    function setWithdrawTimeLimit(uint64 _timeLimit) external onlyAdmin {
        require(_timeLimit != 0, "Withdraw time limit can't be zero");
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(3)));
        withdrawTimeLimit = _timeLimit;
    }

    function setBorrowingContract(address _address) external onlyAdmin {
        require(_address != address(0) && isContract(_address) != false, "Input address is invalid");
        borrowingContract = _address;
        borrowing = IBorrowing(_address);
    }

    function setTreasury(address _treasury) external onlyAdmin{
        require(_treasury != address(0) && isContract(_treasury) != false, "Input address is invalid");
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(7)));
        treasuryAddress = _treasury;
        treasury = ITreasury(_treasury);
    }

    function setAmintLimit(uint8 percent) external onlyAdmin{
        require(percent != 0, "Amint limit can't be zero");
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(9)));
        amintLimit = percent;  
    }

    function setUsdtLimit(uint64 amount) external onlyAdmin{
        require(amount != 0, "USDT limit can't be zero");
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(10)));
        usdtLimit = amount;  
    }

    function calculateValue(uint128 _price) internal view returns(CalculateValueResult memory) {
        uint128 _amount = 1000;
        uint256 vaultBal = treasury.totalVolumeOfBorrowersAmountinWei();
        uint128 priceDiff;
        uint128 value;
        bool gains;

        if(totalCdsDepositedAmount == 0){
            value = 0;
            gains = true;
        }else{
            if(_price != lastEthPrice){
                // If the current eth price is higher than last eth price,then it is gains
                if(_price > lastEthPrice){
                    priceDiff = _price - lastEthPrice;
                    gains = true;    
                }else{
                    priceDiff = lastEthPrice - _price;
                    gains = false;
                }
            }
            else{
                // If the current eth price is higher than fallback eth price,then it is gains
                if(_price > fallbackEthPrice){
                    priceDiff = _price - fallbackEthPrice;
                    gains = true;   
                }else{
                    priceDiff = fallbackEthPrice - _price;
                    gains = false;
                }
            }
            value = uint128((_amount * vaultBal * priceDiff * 1e6) / (PRECISION * totalCdsDepositedAmount));
        }
        return CalculateValueResult(value,gains);
    }

    /**
     * @dev calculate cumulative rate
     * @param fees fees to split
     */
    function calculateCumulativeRate(uint128 fees) public onlyBorrowingContract{
        require(fees != 0,"Fees should not be zero");
        totalCdsDepositedAmountWithOptionFees += fees;
        uint128 netCDSPoolValue = uint128(totalCdsDepositedAmountWithOptionFees);
        uint128 percentageChange = (fees * PRECISION)/netCDSPoolValue;
        uint128 currentCumulativeRate;
        if(treasury.noOfBorrowers() == 0){
            currentCumulativeRate = (1 * PRECISION) + percentageChange;
            lastCumulativeRate = currentCumulativeRate;
        }else{
            currentCumulativeRate = lastCumulativeRate * ((1 * PRECISION) + percentageChange);
            lastCumulativeRate = (currentCumulativeRate/PRECISION);
        }
    }

    /**
     * @param value cumulative value to add or subtract
     * @param gains if true,add value else subtract 
     */
    function setCumulativeValue(uint128 value,bool gains) internal{
        if(gains){
            // If the cumulativeValue is positive
            if(cumulativeValueSign){
                // Add value to cumulativeValue
                cumulativeValue += value;
            }else{
                // if the cumulative value is greater than value 
                if(cumulativeValue > value){
                    // Remains in negative
                    cumulativeValue -= value;
                }else{
                    // Going to postive since value is higher than cumulative value
                    cumulativeValue = value - cumulativeValue;
                    cumulativeValueSign = true;
                }
            }
        }else{
            // If cumulative value is in positive
            if(cumulativeValueSign){
                if(cumulativeValue > value){
                    // Cumulative value remains in positive
                    cumulativeValue -= value;
                }else{
                    // Going to negative since value is higher than cumulative value
                    cumulativeValue = value - cumulativeValue;
                    cumulativeValueSign = false;
                }
            }else{
                // Cumulative value is in negative
                cumulativeValue += value;
            }
        }
    }

    function updateLiquidationInfo(uint128 index,LiquidationInfo memory liquidationData) external onlyBorrowingContract{
        liquidationIndexToInfo[index] = liquidationData;
    }

    function updateTotalAvailableLiquidationAmount(uint256 amount) external onlyBorrowingContract{
        totalAvailableLiquidationAmount -= amount;
    }

    function updateTotalCdsDepositedAmount(uint128 _amount) external onlyBorrowingContract{
        totalCdsDepositedAmount -= _amount;
    }

    function updateTotalCdsDepositedAmountWithOptionFees(uint128 _amount) external onlyBorrowingContract{
        totalCdsDepositedAmountWithOptionFees -= _amount;
    }

}
