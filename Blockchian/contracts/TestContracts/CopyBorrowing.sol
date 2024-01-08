// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interface/CDSInterface.sol";
import "../interface/ITrinityToken.sol";
import "../interface/IProtocolToken.sol";
import "../interface/ITreasury.sol";
import "../interface/IOptions.sol";
import "hardhat/console.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract BorrowingTest is Ownable {

    error Borrowing_DepositFailed();
    error Borrowing_GettingETHPriceFailed();
    error Borrowing_MUSDMintFailed();
    error Borrowing_pTokenMintFailed();
    error Borrowing_WithdrawMUSDTransferFailed();
    error Borrowing_WithdrawEthTransferFailed();
    error Borrowing_WithdrawBurnFailed();
    error Borrowing_LiquidateBurnFailed();
    error Borrowing_LiquidateEthTransferToCdsFailed();

    ITrinityToken public Trinity; // our stablecoin

    CDSInterface public cds;

    IProtocolToken public protocolToken; // abond stablecoin

    ITreasury public treasury;

    IOptions public options; // options contract interface

    uint256 private _downSideProtectionLimit;
    
    enum DownsideProtectionLimitValue {
        // 0: deside Downside Protection limit by percentage of eth price in past 3 months
        ETH_PRICE_VOLUME,
        // 1: deside Downside Protection limit by CDS volume divided by borrower volume.
        CDS_VOLUME_BY_BORROWER_VOLUME
    }

    address public treasuryAddress; // treasury contract address
    address public cdsAddress; // CDS contract address
    address public admin; // admin address
    uint8 private LTV; // LTV is a percentage eg LTV = 60 is 60%, must be divided by 100 in calculations
    uint8 public APY; 
    uint256 public totalNormalizedAmount; // total normalized amount in protocol
    address public priceFeedAddress; // ETH USD pricefeed address
    uint128 public lastEthprice; // previous eth price
    uint256 public lastEthVaultValue; // previous eth vault value
    uint256 public lastCDSPoolValue; // previous CDS pool value
    uint256 public lastTotalCDSPool;
    uint256 public lastCumulativeRate; // previous cumulative rate
    uint128 private lastEventTime;
    uint128 public noOfLiquidations; // total number of liquidation happened till now
    uint256 public totalAmintSupply; // Total amint supply
    uint256 public totalDiracSupply; // total abond supply

    uint128 PRECISION = 1e6;
    uint128 CUMULATIVE_PRECISION = 1e7;
    uint128 RATIO_PRECISION = 1e4;
    uint128 RATE_PRECISION = 1e27;

    event Deposit(uint64 index,uint256 depositedAmount,uint256 borrowAmount,uint256 normalizedAmount);
    event Withdraw(uint256 borrowDebt,uint128 withdrawAmount,uint128 noOfAbond);

    constructor(
        address _tokenAddress,
        address _cds,
        address _protocolToken,
        address _priceFeedAddress
        ){
        Trinity = ITrinityToken(_tokenAddress);
        cds = CDSInterface(_cds);
        cdsAddress = _cds;
        protocolToken = IProtocolToken(_protocolToken);
        priceFeedAddress = _priceFeedAddress;                       //0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
        lastEthprice = uint128(getUSDValue());
        lastEventTime = uint128(block.timestamp);
    }

    modifier onlyAdmin(){
        require(msg.sender == admin);
        _;
    }
    modifier onlyTreasury(){
        require(msg.sender == treasuryAddress);
        _;
    }

    // Function to check if an address is a contract
    function isContract(address addr) internal view returns (bool) {
    uint size;
    assembly {
        size := extcodesize(addr)
    }
    return size > 0;
    }

    /**
     * @dev set Treasury contract
     * @param _treasury treasury contract address
     */

    function initializeTreasury(address _treasury) external onlyOwner{
        require(_treasury != address(0) && isContract(_treasury) != false, "Treasury must be contract address & can't be zero address");
        treasury = ITreasury(_treasury);
        treasuryAddress = _treasury;
    }

    /**
     * @dev set Options contract
     * @param _options option contract address
     */
    function setOptions(address _options) external onlyOwner{
        require(_options != address(0) && isContract(_options) != false, "Options must be contract address & can't be zero address");
        options = IOptions(_options);
    }
    /**
     * @dev set admin address
     * @param _admin  admin address
     */
    function setAdmin(address _admin) external onlyOwner{
        require(_admin != address(0) && isContract(_admin) != true, "Admin can't be contract address & zero address");
        admin = _admin;    
    }

    /**
     * @dev Transfer Trinity token to the borrower
     * @param _borrower Address of the borrower to transfer
     * @param amount deposited amount of the borrower
     * @param _ethPrice current eth price
     */
    function _transferToken(address _borrower,uint256 amount,uint128 _ethPrice,uint256 optionFees) internal returns(uint256){
        require(_borrower != address(0), "Borrower cannot be zero address");
        require(LTV != 0, "LTV must be set to non-zero value before providing loans");
        
        uint256 tokenValueConversion = amount * _ethPrice; // dummy data

        // tokenValueConversion is in USD, and our stablecoin is pegged to USD in 1:1 ratio
        // Hence if tokenValueConversion = 1, then equivalent stablecoin tokens = tokenValueConversion

        uint256 tokensToLend = (tokenValueConversion * LTV) / RATIO_PRECISION;

        //Call the mint function in Trinity
        //Mint 80% - options fees to borrower
        bool minted = Trinity.mint(_borrower, (tokensToLend - optionFees));

        //Mint options fees to treasury
        bool treasuryMint = Trinity.mint(treasuryAddress,optionFees);

        if(!minted){
            revert Borrowing_MUSDMintFailed();
        }

        if(!treasuryMint){
            revert Borrowing_MUSDMintFailed();
        }
        totalAmintSupply = Trinity.totalSupply();
        return tokensToLend - optionFees;
    }

    /**
     * @dev Transfer Abond token to the borrower
     * @param _toAddress Address of the borrower to transfer
     * @param _amount adond amount to transfer
     * @param _bondRatio ratio of abond
     */

    function _mintPToken(address _toAddress,uint256 _amount, uint64 _bondRatio) internal returns(uint128){
        require(_toAddress != address(0), "Borrower cannot be zero address");
        require(_amount != 0,"Amount can't be zero");

        // PToken:Trinity = 4:1
        uint128 amount = (uint128(_amount) * 100)/(_bondRatio*100);

        //Call the mint function in ProtocolToken
        bool minted = protocolToken.mint(_toAddress,amount);

        if(!minted){
            revert Borrowing_pTokenMintFailed();
        }
        totalDiracSupply = protocolToken.totalSupply();
        return amount;
    }

    /**
    * @dev This function takes ethPrice, depositTime, percentageOfEth and receivedType parameters to deposit eth into the contract and mint them back the Trinity tokens.
    * @param _ethPrice get current eth price 
    * @param _depositTime get unixtime stamp at the time of deposit
    * @param _strikePercent percentage increase of eth price
    * @param _strikePrice strike price which the user opted
    * @param _volatility eth volatility
    **/

    function depositTokens (uint128 _ethPrice,uint64 _depositTime,IOptions.StrikePrice _strikePercent,uint64 _strikePrice,uint256 _volatility) external payable {
        require(msg.value > 0, "Cannot deposit zero tokens");
        require(msg.sender.balance > msg.value, "You do not have sufficient balance to execute this transaction");

        //Call calculateInverseOfRatio function to find ratio
        uint64 ratio = _calculateRatio(msg.value,uint128(_ethPrice));
        require(ratio >= (2 * RATIO_PRECISION),"Not enough fund in CDS");
        
        //Call the deposit function in Treasury contract
        (bool deposited,uint64 index) = treasury.deposit{value:msg.value}(msg.sender,_ethPrice,_depositTime);

        // Call calculateOptionPrice in options contract to get options fees
        uint256 optionFees = options.calculateOptionPrice(_volatility,msg.value,_strikePercent);

        //Check whether the deposit is successfull
        if(!deposited){
            revert Borrowing_DepositFailed();
        }

        // Call the transfer function to mint Trinity and Get the borrowedAmount
        uint256 borrowAmount = _transferToken(msg.sender,msg.value,_ethPrice,optionFees);

        // Call calculateCumulativeRate in cds to split fees to cds users
        cds.calculateCumulativeRate(uint128(optionFees));

        //Get the deposit details from treasury
        (,ITreasury.DepositDetails memory depositDetail) = treasury.getBorrowing(msg.sender,index);
        depositDetail.borrowedAmount = uint128(borrowAmount);
        depositDetail.optionFees = uint128(optionFees);

        //Update variables in treasury
        treasury.updateHasBorrowed(msg.sender,true);
        treasury.updateTotalBorrowedAmount(msg.sender,borrowAmount);

        //Call calculateCumulativeRate() to get currentCumulativeRate
        uint256 currentCumulativeRate = calculateCumulativeRate();

        // Calculate normalizedAmount
        uint256 normalizedAmount = (borrowAmount * RATE_PRECISION * RATE_PRECISION)/currentCumulativeRate;

        depositDetail.normalizedAmount = uint128(normalizedAmount);
        depositDetail.strikePrice = _strikePrice;

        //Update the deposit details
        treasury.updateDepositDetails(msg.sender,index,depositDetail);

        // Calculate normalizedAmount of Protocol
        totalNormalizedAmount += normalizedAmount;
        lastEthprice = uint128(_ethPrice);
        lastEventTime = uint128(block.timestamp);
        emit Deposit(index,msg.value,borrowAmount,normalizedAmount);
    }

    /**
     * @dev deposit the eth in our protocol to Aave
     */
    function depositToAaveProtocol() external onlyOwner{
        treasury.depositToAave();
    }

    /**
     * @dev withdraw the eth from aave which were already deposited
     */
    function withdrawFromAaveProtocol(uint64 index) external onlyOwner{
        treasury.withdrawFromAave(index);
    }

    /**
     * @dev deposit the eth in our protocol to Compound
     */
    function depositToCompoundProtocol() external onlyOwner{
        treasury.depositToCompound();
    }

    /**
     * @dev withdraw the eth from Compound which were already deposited
     * @param index index of the deposit
     */
    function withdrawFromCompoundProtocol(uint64 index) external onlyOwner{
        treasury.withdrawFromCompound(index);
    }

    /**
    @dev This function withdraw ETH.
    @param _toAddress The address to whom to transfer ETH.
    @param _index Index of the borrow
    @param _ethPrice Current ETH Price.
    @param _withdrawTime time right now
    **/

    function withDraw(address _toAddress, uint64 _index, uint64 _ethPrice, uint64 _withdrawTime, uint64 _bondRatio) external {
        // check is _toAddress in not a zero address and isContract address
        require(_toAddress != address(0) && isContract(_toAddress) != true, "To address cannot be a zero and contract address");

        lastEthprice = uint128(_ethPrice);
        lastEventTime = uint128(block.timestamp);

        (uint64 borrowerIndex,ITreasury.DepositDetails memory depositDetail) = treasury.getBorrowing(msg.sender,_index);

        // check if borrowerIndex in BorrowerDetails of the msg.sender is greater than or equal to Index
        if(borrowerIndex >= _index ) {
            // Check if user amount in the Index is been liquidated or not
            require(!depositDetail.liquidated,"User amount has been liquidated");
            // check if withdrawed in depositDetail in borrowing of msg.seader is false or not
            if(depositDetail.withdrawed == false) {                
                // Check whether it is first withdraw
                if(depositDetail.withdrawNo == 0) {                    
                    
                    // Calculate the borrowingHealth
                    uint128 borrowingHealth = (_ethPrice * 10000) / depositDetail.ethPriceAtDeposit;
                    require(borrowingHealth > 8000,"BorrowingHealth is Low");
                    // Calculate th borrower's debt
                    uint256 borrowerDebt = ((depositDetail.normalizedAmount * lastCumulativeRate)/RATE_PRECISION);
                    lastCumulativeRate = calculateCumulativeRate()/RATE_PRECISION;
                    // Check whether the Borrower have enough Trinty
                    require(Trinity.balanceOf(msg.sender) >= borrowerDebt, "User balance is less than required");
                            
                    // Update the borrower's data
                    {depositDetail.ethPriceAtWithdraw = _ethPrice;
                    depositDetail.withdrawTime = _withdrawTime;
                    depositDetail.withdrawNo = 1;
                    // Calculate interest for the borrower's debt
                    //uint256 interest = borrowerDebt - depositDetail.borrowedAmount;

                    uint256 discountedETH = ((10*(depositDetail.depositedAmount))/100)*_ethPrice;

                    // Calculate the amount of Trinity to burn and sent to the treasury
                    // uint256 halfValue = (50 *(depositDetail.borrowedAmount))/100;
                    uint256 burnValue = depositDetail.borrowedAmount - discountedETH;

                    // Burn the Trinity from the Borrower
                    bool success = Trinity.burnFromUser(msg.sender, burnValue);
                    if(!success){
                        revert Borrowing_WithdrawBurnFailed();
                    }

                    //Transfer the remaining Trinity to the treasury
                    bool transfer = Trinity.transferFrom(msg.sender,treasuryAddress,discountedETH);
                    if(!transfer){
                        revert Borrowing_WithdrawMUSDTransferFailed();
                    }
                    totalNormalizedAmount -= borrowerDebt;

                    treasury.updateTotalInterest(borrowerDebt - depositDetail.borrowedAmount);

                    // Mint the pTokens
                    uint128 noOfPTokensminted = _mintPToken(msg.sender,discountedETH, _bondRatio);

                    // Update PToken data
                    depositDetail.pTokensAmount = noOfPTokensminted;
                    treasury.updateTotalPTokensIncrease(msg.sender,noOfPTokensminted);
                    // Update deposit details    
                    treasury.updateDepositDetails(msg.sender,_index,depositDetail);}             
                    uint128 ethToReturn;
                    uint128 depositedAmountvalue = (depositDetail.depositedAmount * depositDetail.ethPriceAtDeposit)/_ethPrice;

                    if(borrowingHealth > 10000){
                        ethToReturn = (depositedAmountvalue + (options.withdrawOption(depositDetail.depositedAmount,depositDetail.strikePrice,_ethPrice)));
                    }else if(borrowingHealth == 10000){
                        ethToReturn = depositedAmountvalue;
                    }else if(8000 < borrowingHealth && borrowingHealth < 10000) {
                        ethToReturn = depositDetail.depositedAmount;
                    }else{
                        revert("BorrowingHealth is Low");
                    }
                    ethToReturn = (ethToReturn * 50)/100;
                    console.log("eth to return",ethToReturn);
                bool sent = treasury.withdraw(msg.sender,_toAddress,ethToReturn,_index,_ethPrice);
                if(!sent){
                    revert Borrowing_WithdrawEthTransferFailed();
                }
                totalAmintSupply = Trinity.totalSupply();
                totalDiracSupply = protocolToken.totalSupply();
                emit Withdraw(borrowerDebt,ethToReturn,depositDetail.pTokensAmount);
                }// Check whether it is second withdraw
                else if(depositDetail.withdrawNo == 1){
                    secondWithdraw(
                        _toAddress,
                        _index,
                        _ethPrice,
                        depositDetail.withdrawTime,
                        depositDetail.pTokensAmount,
                        depositDetail.withdrawAmount);
                    totalAmintSupply = Trinity.totalSupply();
                    totalDiracSupply = protocolToken.totalSupply();
                }else{
                    // update withdrawed to true
                    revert("User already withdraw entire amount");
                }
            }else {
                revert("User already withdraw entire amount");
            }
        }else {
            // revert if user doens't have the perticular index
            revert("User doens't have the perticular index");
        }
    }

    /**
     * @dev This function withdraw ETH.
     * @param _toAddress The address to whom to transfer ETH.
     * @param _index Index of the borrow
     * @param pTokensAmount Amount of pTokens transferred.
     * @param withdrawTime time at first withdraw
     * @param ethToReturn ethToReturn
     */

    function secondWithdraw(address _toAddress,uint64 _index,uint64 _ethPrice,uint64 withdrawTime,uint128 pTokensAmount,uint128 ethToReturn) internal {
            // Check whether the first withdraw passed one month
            require(block.timestamp >= (withdrawTime + 30 days),"A month not yet completed since withdraw");
                    
            // Check the user has required pToken
            require(protocolToken.balanceOf(msg.sender) == pTokensAmount,"Don't have enough Protocol Tokens");
            (,ITreasury.DepositDetails memory depositDetail) = treasury.getBorrowing(msg.sender,_index);
            // Update Borrower's Data
            treasury.updateTotalDepositedAmount(msg.sender,uint128(depositDetail.depositedAmount));
            depositDetail.depositedAmount = 0;
            depositDetail.withdrawed = true;
            depositDetail.withdrawNo = 2;
            treasury.updateTotalPTokensDecrease(msg.sender,pTokensAmount);
            depositDetail.pTokensAmount = 0;
            treasury.updateDepositDetails(msg.sender,_index,depositDetail);

            bool transfer = Trinity.burnFromUser(treasuryAddress, ((depositDetail.borrowedAmount*50)/100));
            if(!transfer){
                revert Borrowing_WithdrawBurnFailed();
            }
            bool success = protocolToken.burnFromUser(msg.sender,pTokensAmount);
            if(!success){
                revert Borrowing_WithdrawBurnFailed();
            }
            // Call withdraw function in Treasury
            bool sent = treasury.withdraw(msg.sender,_toAddress,ethToReturn,_index,_ethPrice);
            if(!sent){
                revert Borrowing_WithdrawEthTransferFailed();
            }
    }
    
    // function getBorrowDetails(address _user, uint64 _index) public view returns(DepositDetails){
    //     return Borrowing[_user].DepositDetails[_index];
    // }





    /**
     * @dev This function liquidate ETH which are below downside protection.
     * @param _user The address to whom to liquidate ETH.
     * @param _index Index of the borrow
     * @param currentEthPrice Current ETH Price.
     */

    function liquidate(address _user,uint64 _index,uint64 currentEthPrice) external onlyAdmin{

        // Check whether the liquidator 
        require(_user != address(0), "To address cannot be a zero address");
        require(msg.sender != _user,"You cannot liquidate your own assets!");
        address borrower = _user;
        uint64 index = _index;
        ++noOfLiquidations;

        // Get the borrower details
        (,ITreasury.DepositDetails memory depositDetail) = treasury.getBorrowing(borrower,index);
        require(!depositDetail.liquidated,"Already Liquidated");
        require(depositDetail.depositedAmount <= treasury.getBalanceInTreasury(),"Not enough funds in treasury");

        // Check whether the position is eligible or not for liquidation
        uint128 ratio = ((currentEthPrice * 10000) / depositDetail.ethPriceAtDeposit);
        require(ratio <= 8000,"You cannot liquidate");

        //Update the position to liquidated     
        depositDetail.liquidated = true;

        // Calculate borrower's debt 
        uint256 borrowerDebt = ((depositDetail.normalizedAmount * lastCumulativeRate)/RATE_PRECISION);
        lastCumulativeRate = calculateCumulativeRate()/RATE_PRECISION;
        uint128 returnToTreasury = uint128(borrowerDebt) /*+ uint128 fees*/;
        uint128 returnToDirac = ((((depositDetail.depositedAmount * depositDetail.ethPriceAtDeposit)/100) - returnToTreasury) * 10)/100;
        uint128 cdsProfits = ((depositDetail.depositedAmount * depositDetail.ethPriceAtDeposit)/100) - returnToTreasury - returnToDirac;
        uint128 liquidationAmountNeeded = returnToTreasury + returnToDirac;
        
        CDSInterface.LiquidationInfo memory liquidationInfo;
        liquidationInfo = CDSInterface.LiquidationInfo(liquidationAmountNeeded,cdsProfits,depositDetail.depositedAmount,cds.totalAvailableLiquidationAmount());

        cds.updateLiquidationInfo(noOfLiquidations,liquidationInfo);
        cds.updateTotalCdsDepositedAmount(liquidationAmountNeeded);
        cds.updateTotalAvailableLiquidationAmount(liquidationAmountNeeded);
        //Update totalInterestFromLiquidation
        uint256 totalInterestFromLiquidation = uint256(returnToTreasury - borrowerDebt + returnToDirac);
        treasury.updateTotalInterestFromLiquidation(totalInterestFromLiquidation);
        treasury.updateDepositDetails(borrower,index,depositDetail);

        // Burn the borrow amount
        treasury.approveAmint(address(this),depositDetail.borrowedAmount);
        bool success = Trinity.burnFromUser(treasuryAddress, depositDetail.borrowedAmount);
        if(!success){
            revert Borrowing_LiquidateBurnFailed();
        }
        totalAmintSupply = Trinity.totalSupply();
        // Transfer ETH to CDS Pool
    }

    /**
     * @dev get the usd value of ETH
     */
    function getUSDValue() public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(price) / PRECISION);
    }

    function setLTV(uint8 _LTV) external onlyOwner {
        LTV = _LTV;
    }

    function getLTV() public view returns(uint8){
        return LTV;
    }

    /**
     * @dev update the last eth vault value
     * @param _amount eth vault value
     */
    function updateLastEthVaultValue(uint256 _amount) external onlyTreasury{
        require(_amount != 0,"Last ETH vault value can't be zero");
        lastEthVaultValue -= _amount;
    }

    /**
     * @dev calculate the ratio of CDS Pool/Eth Vault
     * @param _amount amount to be depositing
     * @param currentEthPrice current eth price in usd
     */
    function _calculateRatio(uint256 _amount,uint currentEthPrice) internal returns(uint64){

        uint256 netPLCdsPool;

        if(currentEthPrice == 0){
            revert Borrowing_GettingETHPriceFailed();
        }

        // Get the number of Borrowers
        uint128 noOfBorrowers = treasury.noOfBorrowers();

        // Calculate net P/L of CDS Pool
        if(currentEthPrice > lastEthprice){
            netPLCdsPool = (currentEthPrice - lastEthprice) * noOfBorrowers;
        }else{
            netPLCdsPool = (lastEthprice - currentEthPrice) * noOfBorrowers;
        }

        uint256 currentEthVaultValue;
        uint256 currentCDSPoolValue;
 
        // Check it is the first deposit
        if(noOfBorrowers == 0){

            // Calculate the ethVault value
            lastEthVaultValue = _amount * currentEthPrice;

            // Set the currentEthVaultValue to lastEthVaultValue for next deposit
            currentEthVaultValue = lastEthVaultValue;

            // Get the total amount in CDS
            lastTotalCDSPool = cds.totalCdsDepositedAmount();

            if (currentEthPrice >= lastEthprice){
                lastCDSPoolValue = lastTotalCDSPool + netPLCdsPool;
            }else{
                lastCDSPoolValue = lastTotalCDSPool - netPLCdsPool;
            }

            // Set the currentCDSPoolValue to lastCDSPoolValue for next deposit
            currentCDSPoolValue = lastCDSPoolValue;
        }else{

            currentEthVaultValue = lastEthVaultValue + (_amount * currentEthPrice);
            lastEthVaultValue = currentEthVaultValue;

            uint256 latestTotalCDSPool = cds.totalCdsDepositedAmount();

            if(currentEthPrice >= lastEthprice){
                currentCDSPoolValue = lastCDSPoolValue + (latestTotalCDSPool - lastTotalCDSPool) + netPLCdsPool;
            }else{
                currentCDSPoolValue = lastCDSPoolValue + (latestTotalCDSPool - lastTotalCDSPool) - netPLCdsPool;
            }

            lastTotalCDSPool = latestTotalCDSPool;
            lastCDSPoolValue = currentCDSPoolValue;
        }

        // Calculate ratio by dividing currentEthVaultValue by currentCDSPoolValue,
        // since it may return in decimals we multiply it by 1e6
        uint64 ratio = uint64((currentCDSPoolValue * CUMULATIVE_PRECISION)/currentEthVaultValue);
        return ratio;
    }

    function setAPY(uint8 _apy) external onlyOwner{
        require(_apy != 0,"APY should not be zero");
        APY = _apy;
    }

    function getAPY() public view returns(uint8){
        return APY;
    }

    /**
     * @dev calculate cumulative rate 
     */
    function calculateCumulativeRate() public returns(uint256){
        // Get the noOfBorrowers
        uint128 noOfBorrowers = treasury.noOfBorrowers();

        uint128 ratePerSec = 1000000001547125957863212449;
        uint256 currentCumulativeRate;

        //If first event
        if(noOfBorrowers == 0){
            currentCumulativeRate = ratePerSec;
            lastCumulativeRate = currentCumulativeRate;
        }else{
            uint256 timeInterval = uint128(block.timestamp) - lastEventTime;
            // console.log("TIME INTERVAL",timeInterval);
            currentCumulativeRate = uint256(lastCumulativeRate * _rpow(ratePerSec,timeInterval,RATE_PRECISION));
            lastCumulativeRate = currentCumulativeRate/RATE_PRECISION;
        }
        return currentCumulativeRate;
    }

    function _rpow(uint x, uint n, uint b) internal pure returns (uint z) {
      assembly {
        switch x case 0 {switch n case 0 {z := b} default {z := 0}}
        default {
          switch mod(n, 2) case 0 { z := b } default { z := x }
          let half := div(b, 2)  // for rounding.
          for { n := div(n, 2) } n { n := div(n,2) } {
            let xx := mul(x, x)
            if iszero(eq(div(xx, x), x)) { revert(0,0) }
            let xxRound := add(xx, half)
            if lt(xxRound, xx) { revert(0,0) }
            x := div(xxRound, b)
            if mod(n,2) {
              let zx := mul(z, x)
              if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
              let zxRound := add(zx, half)
              if lt(zxRound, zx) { revert(0,0) }
              z := div(zxRound, b)
            }
          }
        }
      }
    }
}