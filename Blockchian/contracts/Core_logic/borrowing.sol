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
        mapping(uint64=> DepositDetails) depositDetails;
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
    uint128 public totalVolumeOfBorrowersinWei;
    uint128 public totalVolumeOfBorrowersinUSD;
    address public priceFeedAddress;
    uint256 FEED_PRECISION = 1e8; // ETH/USD had 8 decimals

    constructor(
        address _tokenAddress,
        address _cds,
        address _protocolToken,
        address _priceFeedAddress,
        address _treasury
        ) {
        Trinity = ITrinityToken(_tokenAddress);
        cds = CDSInterface(_cds);
        protocolToken = IProtocolToken(_protocolToken);
        treasury = ITreasury(_treasury);
        priceFeedAddress = _priceFeedAddress;                       //0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419

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
     * @dev Transfer Trinity token to the borrower
     * @param _borrower Address of the borrower to transfer
     * @param borrowerIndex Index of the borrower
     */
    function _transferToken(address _borrower, uint64 borrowerIndex) internal {
        require(_borrower != address(0), "Borrower cannot be zero address");
        require(borrowing[_borrower].hasDeposited, "Borrower must have deposited collateral before claiming loan");
        require(LTV != 0, "LTV must be set to non-zero value before providing loans");
        
        uint256 tokenValueConversion = borrowing[_borrower].depositDetails[borrowerIndex].depositedAmount * borrowing[_borrower].depositDetails[borrowerIndex].ethPriceAtDeposit ; // dummy data

        // tokenValueConversion is in USD, and our stablecoin is pegged to USD in 1:1 ratio
        // Hence if tokenValueConversion = 1, then equivalent stablecoin tokens = tokenValueConversion

        uint256 tokensToLend = tokenValueConversion * LTV / 100;
        borrowing[_borrower].hasBorrowed = true;
        borrowing[_borrower].borrowedAmount = tokensToLend;

        Trinity.mint(_borrower, tokensToLend);
    }

    function transferToken(address _borrower, uint64 borrowerIndex) external {
        _transferToken(_borrower,borrowerIndex);
    }


    /**
     * @dev This function takes ethPrice, depositTime, percentageOfEth and receivedType parameters to deposit eth into the contract and mint them back the Trinity tokens.
     * @param _ethPrice get current eth price 
     * @param _depositTime get unixtime stamp at the time of deposit 
     * @param PercentageOfETH If downside protection is of ETH_PRICE_VOLUME in DownsideProtectionLimitValue then PercentageOfETH will be taken as average/volatility percentage of ethereum of past 3 months
     * @param receivedType figure out which type of DownsideProtectionLimitValue enum */

    function depositTokens (uint64 _ethPrice,uint64 _depositTime) external payable {
        require(msg.value > 0, "Cannot deposit zero tokens");
        require(msg.sender.balance > 0, "You do not have sufficient balance to execute this transaction");
        
        //Call the deposit function in Treasury contract
        treasury.deposit{value:msg.value}(msg.sender,_ethPrice,_depositTime);
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
        return uint256(price/FEED_PRECISION);
    }

    function setLTV(uint8 _LTV) external onlyOwner {
        LTV = _LTV;
    }
    
}