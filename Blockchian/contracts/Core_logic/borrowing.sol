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

    ITrinityToken public Trinity; // our stablecoin

    CDSInterface public cds;

    IProtocolToken public protocolToken;

    ITreasury public treasury;

    uint256 private _downSideProtectionLimit;

    struct DepositDetails{

        uint64 depositedTime;
        uint128 depositedAmount;
        uint64 downsidePercentage;
        uint64 ethPriceAtDeposit;
        bool withdrawed;
        bool liquidated;
        uint64 ethPriceAtWithdraw;
        uint64 withdrawTime;
    }
    

    struct BorrowerDetails {
        //uint256 depositedAmount;
        mapping(uint64 => DepositDetails) depositDetails;
        uint256 borrowedAmount;
        bool hasBorrowed;
        bool hasDeposited;
        //uint64 downsidePercentage;
        //uint128 ETHPrice;
        //uint64 depositedTime;
        uint64 borrowerIndex;
    }

    enum DownsideProtectionLimitValue {
        // 0: deside Downside Protection limit by percentage of eth price in past 3 months
        ETH_PRICE_VOLUME,
        // 1: deside Downside Protection limit by CDS volume divided by borrower volume.
        CDS_VOLUME_BY_BORROWER_VOLUME
    }

    mapping(address => BorrowerDetails) public borrowing;

    uint8 private LTV; // LTV is a percentage eg LTV = 60 is 60%, must be divided by 100 in calculations
    uint8 private APY;
    uint128 public totalVolumeOfBorrowersinWei;
    uint128 public totalVolumeOfBorrowersinUSD;
    address public priceFeedAddress;
    uint128 public lastEthprice;
    uint256 public lastEthVaultValue;
    uint256 public lastCDSPoolValue;
    uint256 public lastTotalCDSPool;
    uint128 lastCumulativeRate;
    uint128 private lastEventTime;
    uint128 FEED_PRECISION = 1e10; // ETH/USD had 8 decimals
    uint128 PRECISION = 1e28;

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
    }

    /**
     * @dev Transfer Trinity token to the borrower
     * @param _borrower Address of the borrower to transfer
     * @param amount deposited amount of the borrower
     * @param _ethPrice current eth price
     */
    function _transferToken(address _borrower,uint256 amount,uint128 _ethPrice) internal {
        require(_borrower != address(0), "Borrower cannot be zero address");
        require(LTV != 0, "LTV must be set to non-zero value before providing loans");
        
        uint256 tokenValueConversion = amount * _ethPrice; // dummy data

        // tokenValueConversion is in USD, and our stablecoin is pegged to USD in 1:1 ratio
        // Hence if tokenValueConversion = 1, then equivalent stablecoin tokens = tokenValueConversion

        uint256 tokensToLend = tokenValueConversion * LTV / 100;
        borrowing[_borrower].hasBorrowed = true;
        borrowing[_borrower].borrowedAmount = tokensToLend;

        //Call the mint function in Trinity
        bool minted = Trinity.mint(_borrower, tokensToLend);
        
        if(!minted){
            revert Borrowing_MintFailed();
        }
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
        uint40 ratio = calculateRatio(msg.value,uint128(_ethPrice));
        require(ratio < (5 * FEED_PRECISION),"Not enough fund in CDS");
        
        //Call the deposit function in Treasury contract
        bool deposited = treasury.deposit{value:msg.value}(msg.sender,_ethPrice,_depositTime);

        //Check whether the deposit is successfull
        if(!deposited){
            revert Borrowing_DepositFailed();
        }
        lastEthprice = uint128(_ethPrice);
        lastEventTime = uint128(block.timestamp);
        // Call the transfer function to mint Trinity
        _transferToken(msg.sender,msg.value,_ethPrice);
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

        uint64 Index = _index;

        // check if borrowerIndex in BorrowerDetails of the msg.sender is greater than or equal to Index
        if( borrowing[msg.sender].borrowerIndex >= Index ) {
            // Check if user amount in the Index is been liquidated or not
            require(borrowing[msg.sender].depositDetails[Index].liquidated != true ," User amount has been liquidated");
            // check if withdrawed in depositDetails in borrowing of msg.seader is false or not
            if( borrowing[msg.sender].depositDetails[Index].withdrawed  != false ) {
                //revert if the value of withdrawed is true
                revert("User have withdrawed the amount");

            }
            else {
                borrowing[msg.sender].depositDetails[Index].withdrawed = true;
            }
        }
        else {
            // revert if user doens't have the perticular index
            revert("User doens't have the perticular index");
        }

        uint128 depositEthPrice = borrowing[msg.sender].depositDetails[Index].ethPriceAtDeposit;

        // Also check if user have sufficient Trinity balance what we have given at the time of deposit
        require(borrowing[msg.sender].depositDetails[Index].depositedAmount <= Trinity.balanceOf(msg.sender) ,"User doesn't enough trinity" );

        // compare ethPrice at the time of deposit and at the time of withdraw

        // check the downSideProtection of the index and calculate downsideProtectionValue
        uint128 depositedAmount = borrowing[msg.sender].depositDetails[Index].depositedAmount;
        uint64 downsideProtectionPercentage = borrowing[msg.sender].depositDetails[Index].downsidePercentage;
        uint128 DownsideProtectionValue = ( depositedAmount * downsideProtectionPercentage ) / 100;

        // Convert downsideProtectionPercentage to Hi to see at what value we should liquidate
        // we are converting downsideProtection to bips(100.00%)
        uint64 downsideProtection = (downsideProtectionPercentage * 100);

        // calculate the health of the borrowing position and convert it in to multiple of 100
        uint borrowingHealth = ( _ethPrice * 10000) / depositEthPrice ;

        // if borrowingHealth is lessThan / equal to 10000 which is equal to(1)
        if( borrowingHealth <= 10000 ) {

            // if borrowingHealth is greater than 10000 - (downsideProtection / 2)
            if (borrowingHealth > 10000 -  (downsideProtection / 2)) {
                // calculate the value of the deposited eth with current price of eth
                uint128 currentValueOfDepositedAmount = (depositedAmount * _ethPrice);

                // revert if user doesn't have enough Trinity token
                require(Trinity.balanceOf(msg.sender) >= currentValueOfDepositedAmount, "User balance is less than required");
                
                // change withdrawed to true
                borrowing[msg.sender].depositDetails[Index].withdrawed = true;

                // update eth price at withdraw
                borrowing[msg.sender].depositDetails[Index].ethPriceAtWithdraw = _ethPrice;

                // update withdraw time
                borrowing[msg.sender].depositDetails[Index].withdrawTime = _withdrawTime;

                // burn Trinity token from user of value currentValueOfDepositedAmount
                Trinity.burnFrom(msg.sender, currentValueOfDepositedAmount);

                //calculate value depositedEthValue - currentValueOfDepositedAmount
                uint128 valueToBeBurnedFromCDS = (depositedAmount * depositEthPrice) - currentValueOfDepositedAmount;

                // call approvel function from CDS to burn Trinity from CDS
                cds.approval(address(this), valueToBeBurnedFromCDS);
                
                // burn valueToBeBurnedFromCDS from CDS
                Trinity.burnFrom(address(cds), valueToBeBurnedFromCDS); //! CDS should approve borrowing contract to burn Trinity.
                
                // transfer the value of eth
                (bool sent, bytes memory data) = msg.sender.call{value: depositedAmount}("");

                // call should be successfully
                require(sent, "Failed to send ether in borrowingHealth > downsideProtection / 2");
            }
            //  else, if ethPriceAtWithdraw is above (ethPriceAtDeposit-downsideProtectionValue) and below ethPriceAtDeposit
            else {
                //      calculate the difference and get the difference amount from CDS and transfer it to the user
                uint128 depositWithdrawPriceDiff = depositEthPrice - _ethPrice;
            }
        }
  
       
       
       
        // update withdrawed amount and totalborrowedAmount in borrowing and amountAvailableToBorrow in cds
        // Transfer Trinity token to the user
        // else ethPriceAtDeposit < ethPriceAtWithdraw
        // calculate the difference between ethPriceAtDeposit and ethPriceAtWithdraw
        // transfer difference to cds
        // transfer remaining amount to the user.
        // emit event withdrawBorrow having index, toAddress, withdrawEthPrice, DepositEthPrice
        // 


    }
    
    // function getBorrowDetails(address _user, uint64 _index) public view returns(DepositDetails){
    //     return Borrowing[_user].DepositDetails[_index];
    // }





    //To liquidate a users eth by any other user,

    function Liquidate(uint64 index,uint64 currentEthPrice,uint64 protocolTokenValue, address _user) external{

        //To check if the ratio is less than 0.8 & converting into Bips
        require(msg.sender!=_user,"You cannot liquidate your own assets!");
        uint64 Index = index;
        uint128 ratio = (currentEthPrice * 10000 / borrowing[_user].depositDetails[index].ethPriceAtDeposit);
        uint64 downsideProtectionPercentage = borrowing[msg.sender].depositDetails[Index].downsidePercentage;
        //converting percentage to bips
        uint64 downsideProtection = downsideProtectionPercentage * 100;
        require(ratio<downsideProtection,"You cannot liquidate");
        //Token liquidator needs to provide for liquidating
        
        uint128 TokenNeededToLiquidate = (borrowing[_user].depositDetails[index].ethPriceAtDeposit - currentEthPrice)*borrowing[_user].depositDetails[index].depositedAmount;
        

        borrowing[msg.sender].depositDetails[Index].liquidated = true;
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

    function calculateRatio(uint256 _amount,uint currentEthPrice) internal returns(uint40){

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
        uint40 ratio = uint40((currentCDSPoolValue * PRECISION)/currentEthVaultValue);
        return ratio;
    }

    function setAPY(uint8 _apy) external onlyOwner{
        APY = _apy;
    }

    function getAPY() public view returns(uint8){
        return APY;
    }

    function calculateCumulativeRate(uint256 _amount) public returns(uint128){
        // Get the APY
        uint8 apy = getAPY();

        // Get the noOfBorrowers
        uint128 noOfBorrowers = treasury.noOfBorrowers();

        // Calculate the rate/sec
        uint128 nThpower =  (1/365 days);
        uint256 apyPerSecond =  (apy/100) ** (nThpower);
        uint128 ratePerSec = 1 + apyPerSecond;

        uint128 currentCumulativeRate;
        uint256 normalizedAmount;

        if(noOfBorrowers == 0){
            currentCumulativeRate = ratePerSec;
            lastCumulativeRate = currentCumulativeRate;
        }else{
            currentCumulativeRate = ratePerSec * lastCumulativeRate * (uint128(block.timestamp) - lastEventTime);
            lastCumulativeRate = currentCumulativeRate;
        }

        normalizedAmount = _amount * currentCumulativeRate;
        return currentCumulativeRate;
    }
}