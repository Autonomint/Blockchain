// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interface/CDSInterface.sol";
import "../interface/ITrinityToken.sol";
import "../interface/IProtocolToken.sol";
import "../interface/ITreasury.sol";
import "hardhat/console.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract Borrowing is Ownable {

    error Borrowing_DepositFailed();
    error Borrowing_MintFailed();
    error Borrowing_TreasuryBalanceZero();
    error Borrowing_GettingETHPriceFailed();
    error Borrowing_LowBorrowingHealth();

    ITrinityToken public Trinity; // our stablecoin

    CDSInterface public cds;

    IProtocolToken public protocolToken;

    ITreasury public treasury;

    uint256 private _downSideProtectionLimit;
    
    enum DownsideProtectionLimitValue {
        // 0: deside Downside Protection limit by percentage of eth price in past 3 months
        ETH_PRICE_VOLUME,
        // 1: deside Downside Protection limit by CDS volume divided by borrower volume.
        CDS_VOLUME_BY_BORROWER_VOLUME
    }

    address public treasuryAddress;
    uint8 private LTV; // LTV is a percentage eg LTV = 60 is 60%, must be divided by 100 in calculations
    uint8 private APY;
    uint128 public totalVolumeOfBorrowersinWei;
    uint128 public totalVolumeOfBorrowersinUSD;
    uint256 public totalNormalizedAmount;
    address public priceFeedAddress;
    uint128 public lastEthprice;
    uint256 public lastEthVaultValue;
    uint256 public lastCDSPoolValue;
    uint256 public lastTotalCDSPool;
    uint128 lastCumulativeRate;
    uint128 private lastEventTime;

    uint128 FEED_PRECISION = 1e10; // ETH/USD had 8 decimals
    uint128 PRECISION = 1e28;
    uint128 RATIO_PRECISION = 1e3;

    constructor(
        address _tokenAddress,
        address _cds,
        address _protocolToken,
        address _priceFeedAddress
        ){
        Trinity = ITrinityToken(_tokenAddress);
        cds = CDSInterface(_cds);
        protocolToken = IProtocolToken(_protocolToken);
        priceFeedAddress = _priceFeedAddress;                       //0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
        lastEthprice = uint128(getUSDValue());
    }

    // Function to check if an address is a contract
    
    function isContract(address addr) internal view returns (bool) {
    uint size;
    assembly {
        size := extcodesize(addr)
    }
    return size > 0;
    }

    function initializeTreasury(address _treasury) external onlyOwner{
        require(_treasury != address(0) && isContract(_treasury) != false, "Treasury must be contract address & can't be zero address");
        treasury = ITreasury(_treasury);
        treasuryAddress = _treasury;
    }

    /**
     * @dev Transfer Trinity token to the borrower
     * @param _borrower Address of the borrower to transfer
     * @param amount deposited amount of the borrower
     * @param _ethPrice current eth price
     */
    function _transferToken(address _borrower,uint256 amount,uint128 _ethPrice) internal returns(uint256){
        require(_borrower != address(0), "Borrower cannot be zero address");
        require(LTV != 0, "LTV must be set to non-zero value before providing loans");
        
        uint256 tokenValueConversion = amount * _ethPrice; // dummy data

        // tokenValueConversion is in USD, and our stablecoin is pegged to USD in 1:1 ratio
        // Hence if tokenValueConversion = 1, then equivalent stablecoin tokens = tokenValueConversion

        uint256 tokensToLend = tokenValueConversion * LTV / 100;

        //Call the mint function in Trinity
        bool minted = Trinity.mint(_borrower, tokensToLend);
        
        if(!minted){
            revert Borrowing_MintFailed();
        }
        return tokensToLend;
    }

    function _mintPToken(address _toAddress,uint256 _amount) internal returns(uint128){
        require(_toAddress != address(0), "Borrower cannot be zero address");
        require(_amount != 0,"Amount can't be zero");

        // PToken:Trinity = 4:1
        uint128 amount = (uint128(_amount) * 25)/100;

        //Call the mint function in ProtocolToken
        bool minted = protocolToken.mint(_toAddress,amount);

        if(!minted){
            revert Borrowing_MintFailed();
        }
        return amount;
    }

    /**
     * @dev This function takes ethPrice, depositTime, percentageOfEth and receivedType parameters to deposit eth into the contract and mint them back the Trinity tokens.
     * @param _ethPrice get current eth price 
     * @param _depositTime get unixtime stamp at the time of deposit 
     */

    function depositTokens (uint128 _ethPrice,uint64 _depositTime) external payable {
        require(msg.value > 0, "Cannot deposit zero tokens");
        require(msg.sender.balance > msg.value, "You do not have sufficient balance to execute this transaction");

        //Call calculateInverseOfRatio function to find ratio
        uint64 ratio = _calculateRatio(msg.value,uint128(_ethPrice));
        require(ratio < (5 * FEED_PRECISION),"Not enough fund in CDS");
        
        //Call the deposit function in Treasury contract
        (bool deposited,uint64 index) = treasury.deposit{value:msg.value}(msg.sender,_ethPrice,_depositTime);

        //Check whether the deposit is successfull
        if(!deposited){
            revert Borrowing_DepositFailed();
        }
        lastEthprice = uint128(_ethPrice);
        lastEventTime = uint128(block.timestamp);
        
        // Call the transfer function to mint Trinity and Get the borrowedAmount
        uint256 borrowAmount = _transferToken(msg.sender,msg.value,_ethPrice);
        treasury.updateHasBorrowed(msg.sender,true);
        treasury.updateBorrowedAmount(msg.sender,index,uint128(borrowAmount));
        treasury.updateTotalBorrowedAmount(msg.sender,borrowAmount);

        //Call calculateCumulativeRate() to get currentCumulativeRatev
        uint128 currentCumulativeRate = calculateCumulativeRate();

        // Calculate normalizedAmount
        uint256 normalizedAmount = borrowAmount/currentCumulativeRate;

        treasury.updateNormalizedAmount(msg.sender,index,uint128(normalizedAmount));

        // Calculate normalizedAmount of Protocol
        totalNormalizedAmount += normalizedAmount;
    }

    function depositToAaveProtocol() external onlyOwner{
        treasury.depositToAave();
    }

    function withdrawFromAaveProtocol(uint64 index,uint256 amount) external onlyOwner{
        treasury.withdrawFromAave(index,amount);
    }

    function depositToCompoundProtocol() external onlyOwner{
        treasury.depositToCompound();
    }

    function withdrawFromCompoundProtocol(uint64 index) external onlyOwner{
        treasury.withdrawFromCompound(index);
    }

    function withDraw(address _toAddress, uint64 _index, uint64 _ethPrice, uint64 _withdrawTime) external {
        // check is _toAddress in not a zero address and isContract address
        require(_toAddress != address(0) && isContract(_toAddress) != true, "To address cannot be a zero and contract address");

        (uint64 borrowerIndex,ITreasury.DepositDetails memory depositDetails) = treasury.getBorrowing(msg.sender,_index);

        // check if borrowerIndex in BorrowerDetails of the msg.sender is greater than or equal to Index
        if(borrowerIndex>= _index ) {
            // Check if user amount in the Index is been liquidated or not
            require(depositDetails.liquidated != true ," User amount has been liquidated");
            // check if withdrawed in depositDetails in borrowing of msg.seader is false or not
            if(depositDetails.withdrawed == false) {                
                // Check whether it is first withdraw
                if(depositDetails.withdrawNo== 0) {                    
                    // Calculate the borrowingHealth
                    uint128 borrowingHealth = (_ethPrice * 10000) / depositDetails.ethPriceAtDeposit;

                    // Check if the borrowingHealth is between 8000(0.8) & 10000(1)
                    if(8000 < borrowingHealth && borrowingHealth < 10000) {
                        // Calculate th borrower's debt
                        uint128 borrowerDebt = depositDetails.normalizedAmount * calculateCumulativeRate();

                        // Check whether the Borrower have enough Trinty
                        require(Trinity.balanceOf(msg.sender) >= borrowerDebt, "User balance is less than required");
                            
                        // Update the borrower's data    
                        treasury.updateethPriceAtWithdraw(msg.sender,_index,_ethPrice);
                        treasury.updateWithdrawTime(msg.sender,_index,_withdrawTime);
                        treasury.updateWithdrawNo(msg.sender,_index,1);

                        // Calculate interest for the borrower's debt
                        uint256 interest = borrowerDebt - depositDetails.borrowedAmount;

                        // Calculate the amount of Trinity to burn and sent to the treasury
                        uint256 halfValue = (50 *(borrowerDebt-interest))/100;

                        // Burn the Trinity from the Borrower
                        Trinity.burnFrom(msg.sender, halfValue);

                        //Transfer the remaining Trinity to the treasury
                        Trinity.transferFrom(msg.sender,treasuryAddress,halfValue);
                        totalNormalizedAmount -= borrowerDebt;

                        uint256 totalInterest = treasury.totalInterest();
                        totalInterest += interest;
                        treasury.updateTotalInterest(totalInterest);

                        // Sent the ETH(depositedAmount) to the toAddress
                        treasury.withdraw(msg.sender,_toAddress,depositDetails.depositedAmount,_index);

                        // Mint the pTokens
                        uint128 noOfPTokensminted = _mintPToken(msg.sender,halfValue);

                        // Update PToken data
                        treasury.updatePTokensAmount(msg.sender,_index,noOfPTokensminted);
                        treasury.updateTotalPTokensIncrease(msg.sender,noOfPTokensminted);
                    }else{
                        revert("BorrowingHealth is Low");
                    }
                }// Check whether it is second withdraw
                else if(depositDetails.withdrawNo == 1){
                    secondWithdraw(
                        _index,
                        _toAddress,
                        depositDetails.withdrawTime,
                        depositDetails.pTokensAmount,
                        depositDetails.depositedAmount);
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

    function secondWithdraw(uint64 _index,address _toAddress,uint64 withdrawTime,uint128 pTokensAmount,uint128 depositedAmount) internal {
            // Check whether the first withdraw passed one month
            require(block.timestamp >= (withdrawTime + 30 days),"A month not yet completed since withdraw");
                    
            // Check the user has required pToken
            require(protocolToken.balanceOf(msg.sender) == pTokensAmount,"Don't have enough Protocol Tokens");
                
            // Update Borrower's Data
            treasury.updateTotalDepositedAmount(msg.sender,uint128(depositedAmount));
            treasury.updateDepositedAmount(msg.sender,_index,0);
            treasury.updateWithdrawed(msg.sender,_index,true);
            treasury.updateWithdrawNo(msg.sender,_index,2);
            treasury.updateTotalPTokensDecrease(msg.sender,pTokensAmount);
            treasury.updatePTokensAmount(msg.sender,_index,0);
            // Burn the pTokens
            protocolToken.burnFrom(msg.sender,pTokensAmount);
            // Call withdraw function in Treasury
            treasury.withdraw(msg.sender,_toAddress,depositedAmount,_index);
    }
    
    // function getBorrowDetails(address _user, uint64 _index) public view returns(DepositDetails){
    //     return Borrowing[_user].DepositDetails[_index];
    // }





    //To liquidate a users eth by any other user,

    function Liquidate(uint64 index,uint64 currentEthPrice,uint64 protocolTokenValue, address _user) external{

        //To check if the ratio is less than 0.8 & converting into Bips
        require(msg.sender!=_user,"You cannot liquidate your own assets!");
        uint64 Index = index;
        uint128 ratio = (currentEthPrice * 10000 / treasury.borrowing[_user].depositDetails[index].ethPriceAtDeposit);
        uint64 downsideProtectionPercentage = treasury.borrowing[msg.sender].depositDetails[Index].downsidePercentage;
        //converting percentage to bips
        uint64 downsideProtection = downsideProtectionPercentage * 100;
        require(ratio<downsideProtection,"You cannot liquidate");
        //Token liquidator needs to provide for liquidating
        
        uint128 TokenNeededToLiquidate = (treasury.borrowing[_user].depositDetails[index].ethPriceAtDeposit - currentEthPrice)*treasury.borrowing[_user].depositDetails[index].depositedAmount;
        

        treasury.borrowing[msg.sender].depositDetails[Index].liquidated = true;
        //Transfer the require amount 
        Trinity.burnFrom(address(this), TokenNeededToLiquidate);
        //Protocol token will be minted for the liquidator
        //multipling by 10 and dividing by 100 to get 10%,  
        //Denominator = 100 * 2(protocol token value in dollar) = 200
        uint128 amountToMint = (110 * TokenNeededToLiquidate) / (100*protocolTokenValue);  

        protocolToken.mint(msg.sender, amountToMint);

    }

    function getUSDValue() public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(price) * FEED_PRECISION);
    }

    function setLTV(uint8 _LTV) external onlyOwner {
        LTV = _LTV;
    }

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
        uint64 ratio = uint64((currentCDSPoolValue * PRECISION)/currentEthVaultValue);
        return ratio;
    }

    function setAPY(uint8 _apy) external onlyOwner{
        APY = _apy;
    }

    function getAPY() public view returns(uint8){
        return APY;
    }

    function calculateCumulativeRate() public returns(uint128){
        // Get the APY
        uint128 apy = uint128(getAPY());

        // Get the noOfBorrowers
        uint128 noOfBorrowers = treasury.noOfBorrowers();

        // r**n = apyRate
        // calculate 1/n
        uint128 nThpower =  ((1 * PRECISION)/365 days);

        // calculate apyRate ( 1 + apy)
        uint256 apyRate =  ((1* RATIO_PRECISION)+(apy * RATIO_PRECISION)/100);

        // calculate rate per second
        uint256 ratePerSec = apyRate ** nThpower;      

        console.log(ratePerSec);        //1.0000000015471259578632124490459

        uint128 currentCumulativeRate;

        //If first event
        if(noOfBorrowers == 0){
            currentCumulativeRate = uint128(ratePerSec);
            lastCumulativeRate = currentCumulativeRate;
        }else{
            currentCumulativeRate = uint128(ratePerSec * lastCumulativeRate * (uint128(block.timestamp) - lastEventTime));
            lastCumulativeRate = currentCumulativeRate;
        }
        return currentCumulativeRate;
    }
}