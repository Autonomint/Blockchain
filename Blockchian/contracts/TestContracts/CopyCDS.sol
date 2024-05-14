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
import "../interface/CDSInterface.sol";
import "../interface/IMultiSign.sol";
import "../lib/CDSLib.sol";
import "hardhat/console.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

contract CDSTest is CDSInterface,Initializable,UUPSUpgradeable,ReentrancyGuardUpgradeable,OApp{

    IAMINT      private amint; // our stablecoin
    IBorrowing  private borrowing; // Borrowing contract interface
    ITreasury   private treasury; // Treasury contrcat interface
    AggregatorV3Interface internal dataFeed;
    IMultiSign  private multiSign;
    IERC20      private usdt; // USDT interface

    address private admin; // admin address
    address private borrowingContract; // borrowing contract address
    address private treasuryAddress; // treasury contract address

    uint128 private lastEthPrice;
    uint128 private fallbackEthPrice;
    uint64  private cdsCount; // cds depositors count
    uint64  private withdrawTimeLimit; // Fixed Time interval between deposit and withdraw
    uint256 public totalCdsDepositedAmount; // total amint and usdt deposited in cds
    uint256 public totalCdsDepositedAmountWithOptionFees;
    uint256 public totalAvailableLiquidationAmount; // total deposited amint available for liquidation
    uint128 private lastCumulativeRate; 
    uint8   private amintLimit; // amint limit in percent
    uint64  private usdtLimit; // usdt limit in number
    uint256 private usdtAmountDepositedTillNow; // total usdt deposited till now
    uint256 private burnedAmintInRedeem;
    uint128 private cumulativeValue;
    bool    private cumulativeValueSign;

    mapping (address => CdsDetails) public cdsDetails;

    // liquidations info based on liquidation numbers
    mapping (uint128 liquidationIndex => LiquidationInfo) public omniChainCDSLiqIndexToInfo;

    using OptionsBuilder for bytes;
    OmniChainCDSData public omniChainCDS;//! omnichainCDS contains global CDS data(all chains)
    uint32 private dstEid;

    function initialize(
        address _amint,
        address priceFeed,
        address _usdt,
        address _multiSign,
        address _endpoint,
        address _delegate
    ) initializer public{
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __oAppinit(_endpoint, _delegate);
        amint = IAMINT(_amint); // amint token contract address
        usdt = IERC20(_usdt);
        multiSign = IMultiSign(_multiSign);
        dataFeed = AggregatorV3Interface(priceFeed);
        lastEthPrice = getLatestData();
        fallbackEthPrice = lastEthPrice;
        omniChainCDS.lastCumulativeRate = CDSLib.PRECISION;
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

    function setDstEid(uint32 _eid) external onlyAdmin{
        require(_eid != 0, "EID can't be zero");
        dstEid = _eid;
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
        uint128 _liquidationAmount
    ) public payable nonReentrant whenNotPaused(IMultiSign.Functions(4)){
        // totalDepositingAmount is usdt and amint
        uint256 totalDepositingAmount = usdtAmount + amintAmount;
        require(totalDepositingAmount != 0, "Deposit amount should not be zero"); // check _amount not zero
        require(
            _liquidationAmount <= (totalDepositingAmount),
            "Liquidation amount can't greater than deposited amount"
        );

        if(usdtAmountDepositedTillNow < usdtLimit){
            if((usdtAmountDepositedTillNow + usdtAmount) <= usdtLimit){
                require(usdtAmount == totalDepositingAmount,'100% of amount must be USDT');
            }else{
                revert("Surplus USDT amount");
            }
        }else{
            require(amintAmount >= (amintLimit * totalDepositingAmount)/100,"Required AMINT amount not met");
            require(amint.balanceOf(msg.sender) >= amintAmount,"Insufficient AMINT balance with msg.sender"); // check if user has sufficient AMINT token
        }

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
            //! updating global data 
            ++omniChainCDS.cdsCount;
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

        //! updating global data 
        omniChainCDS.totalCdsDepositedAmount += totalDepositingAmount;
        omniChainCDS.totalCdsDepositedAmountWithOptionFees += totalDepositingAmount;

        //increment usdtAmountDepositedTillNow
        usdtAmountDepositedTillNow += usdtAmount;

        //! updating global data 
        omniChainCDS.usdtAmountDepositedTillNow += usdtAmount;
        
        //add deposited time of perticular index and amount in cdsAccountDetails
        cdsDetails[msg.sender].cdsAccountDetails[index].depositedTime = uint64(block.timestamp);
        cdsDetails[msg.sender].cdsAccountDetails[index].normalizedAmount = ((totalDepositingAmount * CDSLib.PRECISION)/omniChainCDS.lastCumulativeRate);
       
        cdsDetails[msg.sender].cdsAccountDetails[index].optedLiquidation = _liquidate;
        //If user opted for liquidation
        if(_liquidate){
            cdsDetails[msg.sender].cdsAccountDetails[index].liquidationindex = borrowing.omniChainBorrowingNoOfLiquidations();
            cdsDetails[msg.sender].cdsAccountDetails[index].liquidationAmount = _liquidationAmount;
            cdsDetails[msg.sender].cdsAccountDetails[index].InitialLiquidationAmount = _liquidationAmount;
            totalAvailableLiquidationAmount += _liquidationAmount;
            
            //! updating global data 
            omniChainCDS.totalAvailableLiquidationAmount += _liquidationAmount;
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

        //! getting options since,the src don't know the dst state
        bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        //! calculting fee 
        MessagingFee memory fee = quote(dstEid, FunctionToDo(1), 0, 0, 0, LiquidationInfo(0,0,0,0), 0, _options, false);

        //! Calling Omnichain send function
        send(dstEid, FunctionToDo(1), omniChainCDS, 0, fee, _options);

        emit Deposit(totalDepositingAmount,index,_liquidationAmount,cdsDetails[msg.sender].cdsAccountDetails[index].normalizedAmount,cdsDetails[msg.sender].cdsAccountDetails[index].depositValue);
    }

    /**
     * @dev withdraw amint
     * @param _index index of the deposit to withdraw
     */
    function withdraw(uint64 _index) public payable nonReentrant whenNotPaused(IMultiSign.Functions(5)){
        require(cdsDetails[msg.sender].index >= _index , "user doesn't have the specified index");
        require(cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawed == false,"Already withdrawn");
        
        uint64 _withdrawTime = uint64(block.timestamp);

        require(cdsDetails[msg.sender].cdsAccountDetails[_index].depositedTime + withdrawTimeLimit <= _withdrawTime,"cannot withdraw before the withdraw time limit");

        cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawed = true;

        if (cdsDetails[msg.sender].index == 1 && _index == 1) {
            --cdsCount;
        }

        uint128 ethPrice = getLatestData();
        require(ethPrice != 0,"Oracle Failed");
        // Calculate return amount includes
        // eth Price difference gain or loss
        // option fees
        uint256 optionFees = ((cdsDetails[msg.sender].cdsAccountDetails[_index].normalizedAmount * omniChainCDS.lastCumulativeRate)/CDSLib.PRECISION) - 
            cdsDetails[msg.sender].cdsAccountDetails[_index].depositedAmount;
        uint256 returnAmount = cdsAmountToReturn(msg.sender,_index, ethPrice) + optionFees;
        
        uint256 optionsFeesToGetFromOtherChain = getOptionsFeesProportions(optionFees);

        cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawedAmount = returnAmount;
        cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawedTime =  _withdrawTime;

        //! getting options since,the src don't know the dst state
        bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        //! calculting fee 
        MessagingFee memory fee = quote(
            dstEid, 
            FunctionToDo(2), 
            optionsFeesToGetFromOtherChain, 
            0, 
            0,  
            LiquidationInfo(0,0,0,0), 
            0, 
            _options, 
            false);

        // If user opted for liquidation
        if(cdsDetails[msg.sender].cdsAccountDetails[_index].optedLiquidation){
            returnAmount -= cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount;
            uint128 currentLiquidations = borrowing.omniChainBorrowingNoOfLiquidations();
            uint128 liquidationIndexAtDeposit = cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationindex;
            uint128 ethAmount;
            if(currentLiquidations >= liquidationIndexAtDeposit){
                // Loop through the liquidations that were done after user enters
                for(uint128 i = (liquidationIndexAtDeposit + 1); i <= currentLiquidations; i++){
                    uint128 liquidationAmount = cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount;
                    if(liquidationAmount > 0){
                        LiquidationInfo memory liquidationData = omniChainCDSLiqIndexToInfo[i];

                        uint128 share = (liquidationAmount * 1e10)/uint128(liquidationData.availableLiquidationAmount);
                        uint128 profit;

                        profit = (liquidationData.profits * share)/1e10;
                        cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount += profit;
                        //console.log("cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount",cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount);
                        cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount -= ((liquidationData.liquidationAmount*share)/1e10);
                        ethAmount += (liquidationData.ethAmount * share)/1e10;
                    }
                }
                uint256 returnAmountWithGains = returnAmount + cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount;

                if(ethAmount == 0){
                    totalCdsDepositedAmount -= cdsDetails[msg.sender].cdsAccountDetails[_index].depositedAmount;
                    omniChainCDS.totalCdsDepositedAmount -= cdsDetails[msg.sender].cdsAccountDetails[_index].depositedAmount;

                    totalCdsDepositedAmountWithOptionFees -= (
                        cdsDetails[msg.sender].cdsAccountDetails[_index].depositedAmount + (optionFees - optionsFeesToGetFromOtherChain));
                    omniChainCDS.totalCdsDepositedAmountWithOptionFees -= (
                        cdsDetails[msg.sender].cdsAccountDetails[_index].depositedAmount + optionFees);
                }else{
                    totalCdsDepositedAmount -= (cdsDetails[msg.sender].cdsAccountDetails[_index].depositedAmount - cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount);
                    omniChainCDS.totalCdsDepositedAmount -= (
                        cdsDetails[msg.sender].cdsAccountDetails[_index].depositedAmount 
                        - cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount);
                    totalCdsDepositedAmountWithOptionFees -= (
                        cdsDetails[msg.sender].cdsAccountDetails[_index].depositedAmount - cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount + optionsFeesToGetFromOtherChain);
                    omniChainCDS.totalCdsDepositedAmountWithOptionFees -= (
                        cdsDetails[msg.sender].cdsAccountDetails[_index].depositedAmount - cdsDetails[msg.sender].cdsAccountDetails[_index].liquidationAmount + optionFees);
                }

                if(optionsFeesToGetFromOtherChain > 0){
                    treasury.oftOrNativeReceiveFromOtherChains{ value: msg.value - fee.nativeFee}(
                        ITreasury.FunctionToDo(2),
                        ITreasury.AmintOftTransferData(treasuryAddress, optionsFeesToGetFromOtherChain),
                        ITreasury.NativeTokenTransferData(treasuryAddress, ethAmount));
                }

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
            }

        }else{

            if(optionsFeesToGetFromOtherChain > 0){
                treasury.oftOrNativeReceiveFromOtherChains{ value: msg.value - fee.nativeFee}(
                    ITreasury.FunctionToDo(2),
                    ITreasury.AmintOftTransferData(treasuryAddress, optionsFeesToGetFromOtherChain),
                    ITreasury.NativeTokenTransferData(address(0), 0));
            }
            
            // amint.approve(msg.sender, returnAmount);
            totalCdsDepositedAmount -= cdsDetails[msg.sender].cdsAccountDetails[_index].depositedAmount;
            totalCdsDepositedAmountWithOptionFees -= returnAmount - optionsFeesToGetFromOtherChain;

            omniChainCDS.totalCdsDepositedAmount -= cdsDetails[msg.sender].cdsAccountDetails[_index].depositedAmount;
            omniChainCDS.totalCdsDepositedAmountWithOptionFees -= returnAmount;
            
            cdsDetails[msg.sender].cdsAccountDetails[_index].withdrawedAmount = returnAmount;

            treasury.approveAmint(address(this),returnAmount);
            bool transfer = amint.transferFrom(treasuryAddress,msg.sender, returnAmount); // transfer amount to msg.sender
            require(transfer == true, "Transfer failed in cds withdraw");
        }

        if(treasury.omniChainTreasuryTotalVolumeOfBorrowersAmountinUSD() != 0){
            require(borrowing.calculateRatio(0,ethPrice) > (2 * CDSLib.RATIO_PRECISION),"CDS: Not enough fund in CDS");
        }

        if(ethPrice != lastEthPrice){
            updateLastEthPrice(ethPrice);
        }

        if(optionsFeesToGetFromOtherChain == 0){
            (bool sent,) = payable(msg.sender).call{value: msg.value - fee.nativeFee}("");
            require(sent, "Failed to send Ether");
        }

        //! Calling Omnichain send function
        send(dstEid, FunctionToDo(2), omniChainCDS, optionsFeesToGetFromOtherChain, fee, _options);
        
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
    ) external payable nonReentrant whenNotPaused(IMultiSign.Functions(6)){
        require(_amintAmount != 0,"Amount should not be zero");

        require(amint.balanceOf(msg.sender) >= _amintAmount,"Insufficient balance");
        burnedAmintInRedeem += _amintAmount;
        omniChainCDS.burnedAmintInRedeem += _amintAmount;
        bool transfer = amint.burnFromUser(msg.sender,_amintAmount);
        require(transfer == true, "AMINT Burn failed in redeemUSDT");

        uint128 _usdtAmount = (amintPrice * _amintAmount/usdtPrice);  
          
        treasury.approveUsdt(address(this),_usdtAmount);
        bool success = usdt.transferFrom(treasuryAddress,msg.sender,_usdtAmount);
        require(success == true, "USDT Transfer failed in redeemUSDT");

        //! getting options since,the src don't know the dst state
        bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        //! calculting fee 
        MessagingFee memory fee = quote(
            dstEid, 
            FunctionToDo(1),
            0, 
            0, 
            0,  
            LiquidationInfo(0,0,0,0), 
            0, 
            _options, 
            false);

        //! Calling Omnichain send function
        send(dstEid, FunctionToDo(1), omniChainCDS, 0, fee, _options);
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

        uint256 vaultBal = treasury.omniChainTreasuryTotalVolumeOfBorrowersAmountinWei();

        return CDSLib.calculateValue(
            _price,
            totalCdsDepositedAmount,
            lastEthPrice,
            fallbackEthPrice,
            vaultBal
        );
    }

    /**
     * @dev calculate cumulative rate
     * @param fees fees to split
     */
    function calculateCumulativeRate(uint128 fees) external payable onlyBorrowingContract{
        require(fees != 0,"Fees should not be zero");
        if(totalCdsDepositedAmount > 0){
            totalCdsDepositedAmountWithOptionFees += fees;
        }
        omniChainCDS.totalCdsDepositedAmountWithOptionFees += fees;
        uint128 netCDSPoolValue = uint128(omniChainCDS.totalCdsDepositedAmountWithOptionFees);
        uint128 percentageChange = (fees * CDSLib.PRECISION)/netCDSPoolValue;
        uint128 currentCumulativeRate;
        if(treasury.omniChainTreasuryNoOfBorrowers() == 0){
            currentCumulativeRate = (1 * CDSLib.PRECISION) + percentageChange;
            omniChainCDS.lastCumulativeRate = currentCumulativeRate;
        }else{
            currentCumulativeRate = omniChainCDS.lastCumulativeRate * ((1 * CDSLib.PRECISION) + percentageChange);
            omniChainCDS.lastCumulativeRate = (currentCumulativeRate/CDSLib.PRECISION);
        }

        //! getting options since,the src don't know the dst state
        bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        //! calculting fee 
        MessagingFee memory fee = quote(
            dstEid, 
            FunctionToDo(1), 
            0, 
            0, 
            0, 
            LiquidationInfo(0,0,0,0), 
            0, 
            _options, 
            false);

        //! Calling Omnichain send function
        send(dstEid, FunctionToDo(1), omniChainCDS, 0, fee, _options);
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

    function getOptionsFeesProportions(uint256 optionsFees) internal view returns (uint256){
        uint256 otherChainCDSAmount = omniChainCDS.totalCdsDepositedAmount - totalCdsDepositedAmount;

        uint256 totalOptionFeesInOtherChain = omniChainCDS.totalCdsDepositedAmountWithOptionFees
                - totalCdsDepositedAmountWithOptionFees - otherChainCDSAmount;

        uint256 totalOptionFeesInThisChain = totalCdsDepositedAmountWithOptionFees - totalCdsDepositedAmount; 

        uint256 share = (otherChainCDSAmount * 1e10)/omniChainCDS.totalCdsDepositedAmount;
        uint256 optionsfeesToGet = (optionsFees * share)/1e10;
        uint256 optionsFeesRemaining = optionsFees - optionsfeesToGet;

        if(totalOptionFeesInOtherChain == 0){
            optionsfeesToGet = 0;
        }else{
            if(totalOptionFeesInOtherChain < optionsfeesToGet) {
                optionsfeesToGet = totalOptionFeesInOtherChain;
            }else{
                if(totalOptionFeesInOtherChain > optionsfeesToGet && totalOptionFeesInThisChain < optionsFeesRemaining){
                    optionsfeesToGet += optionsFeesRemaining - totalOptionFeesInThisChain;
                }else{
                    optionsfeesToGet = optionsfeesToGet;
                }
            }
        }
        return optionsfeesToGet;
    }

    function callLzSendFromExternal(
        uint32 _dstEid,
        FunctionToDo functionToDo,
        uint256 optionsFeesToGetFromOtherChain,
        uint256 cdsAmountToGetFromOtherChain,
        uint256 liqAmountToGetFromOtherChain,
        LiquidationInfo memory liquidationInfo,
        uint128 liqIndex,
        MessagingFee memory fee,
        bytes memory _options
    ) external payable onlyBorrowingContract returns (MessagingReceipt memory receipt) {

        bytes memory _payload = abi.encode(
            functionToDo,
            omniChainCDS,
            optionsFeesToGetFromOtherChain,
            cdsAmountToGetFromOtherChain,
            liqAmountToGetFromOtherChain,
            liquidationInfo,
            liqIndex
            );
        
        //! Calling layer zero send function to send to dst chain
        receipt = _lzSend(_dstEid, _payload, _options, fee, payable(msg.sender));
    }

    function send(
        uint32 _dstEid,
        FunctionToDo _functionToDo,
        OmniChainCDSData memory _message,
        uint256 optionsFeesToGetFromOtherChain,
        MessagingFee memory fee,
        bytes memory _options
    ) internal returns (MessagingReceipt memory receipt) {

        LiquidationInfo memory liqInfo;

        bytes memory _payload = abi.encode(
            _functionToDo, 
            _message, 
            optionsFeesToGetFromOtherChain, 
            0, 
            0,
            liqInfo,
            0);
        
        //! Calling layer zero send function to send to dst chain
        receipt = _lzSend(_dstEid, _payload, _options, fee, payable(msg.sender));
    }

    function quote(
        uint32 _dstEid,
        FunctionToDo _functionToDo,
        uint256 optionsFeesToGetFromOtherChain,
        uint256 cdsAmountToGetFromOtherChain,
        uint256 liqAmountToGetFromOtherChain,
        LiquidationInfo memory liquidationInfo,
        uint128 liqIndex,
        bytes memory _options,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(
            _functionToDo,
            omniChainCDS,
            optionsFeesToGetFromOtherChain,
            cdsAmountToGetFromOtherChain,
            liqAmountToGetFromOtherChain,
            liquidationInfo,
            liqIndex);
        fee = _quote(_dstEid, payload, _options, _payInLzToken);
    }

    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {

        OmniChainCDSData memory data;
        FunctionToDo functionToDo;
        uint256 optionsFeesToRemove;
        uint256 cdsAmountToRemove;
        uint256 liqAmountToRemove;
        LiquidationInfo memory liquidationInfo;
        uint128 liqIndex;

        (
            functionToDo, 
            data, 
            optionsFeesToRemove,
            cdsAmountToRemove,
            liqAmountToRemove,
            liquidationInfo,
            liqIndex) = abi.decode(payload, (FunctionToDo, OmniChainCDSData, uint256, uint256, uint256, LiquidationInfo, uint128));

        if(functionToDo == FunctionToDo.UPDATE_GLOBAL){
            omniChainCDS = data;
        }else if(functionToDo == FunctionToDo.UPDATE_INDIVIDUAL){
            totalCdsDepositedAmountWithOptionFees -= optionsFeesToRemove;
            totalCdsDepositedAmount -= cdsAmountToRemove;
            totalAvailableLiquidationAmount -= liqAmountToRemove;
            omniChainCDSLiqIndexToInfo[liqIndex] = liquidationInfo;
            omniChainCDS = data;
        }
    }

    function updateLiquidationInfo(uint128 index,LiquidationInfo memory liquidationData) external onlyBorrowingContract{
        omniChainCDSLiqIndexToInfo[index] = liquidationData;
    }

    function updateTotalAvailableLiquidationAmount(uint256 amount) external onlyBorrowingContract{
        totalAvailableLiquidationAmount -= amount;
        omniChainCDS.totalAvailableLiquidationAmount -= amount;
    }

    function updateTotalCdsDepositedAmount(uint128 _amount) external onlyBorrowingContract{
        totalCdsDepositedAmount -= _amount;
        omniChainCDS.totalCdsDepositedAmount -= _amount;
    }

    function updateTotalCdsDepositedAmountWithOptionFees(uint128 _amount) external onlyBorrowingContract{
        totalCdsDepositedAmountWithOptionFees -= _amount;
        omniChainCDS.totalCdsDepositedAmountWithOptionFees -= _amount;
    }

    function omniChainCDSTotalCdsDepositedAmount() external view returns(uint256){
        return omniChainCDS.totalCdsDepositedAmount;
    }

    function omniChainCDSTotalAvailableLiquidationAmount() external view returns(uint256){
        return omniChainCDS.totalAvailableLiquidationAmount;
    }

    function getCDSDepositDetails(address depositor,uint64 index) external view returns(CdsAccountDetails memory,uint64){
        return (cdsDetails[depositor].cdsAccountDetails[index],cdsDetails[depositor].index);
    }

}
