// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interface/IAmint.sol";
import { State,IABONDToken } from "../interface/IAbond.sol";
import "../interface/IBorrowing.sol";
import "../interface/ITreasury.sol";
import "../interface/AaveInterfaces/IWETHGateway.sol";
import "../interface/AaveInterfaces/IPoolAddressesProvider.sol";
import "../interface/CometMainInterface.sol";
import "../interface/IWETH9.sol";
import "../lib/TreasuryLib.sol";
import "hardhat/console.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

contract Treasury is ITreasury,Initializable,UUPSUpgradeable,ReentrancyGuardUpgradeable,OApp {

    IBorrowing  public borrow;
    IAMINT      public amint;
    IABONDToken public abond;
    IWrappedTokenGatewayV3  public wethGateway; // Weth gateway is used to deposit eth in  and withdraw from aave
    IPoolAddressesProvider  public aavePoolAddressProvider; // To get the current pool  address in Aave
    IERC20  public usdt;
    IERC20  public aToken; // aave token contract
    CometMainInterface public comet; // To deposit in and withdraw eth from compound
    IWETH9 public WETH;

    address public borrowingContract;
    address public cdsContract;  
    address public compoundAddress;
    address public aaveWETH;        //wethGateway Address for Approve

    // Get depositor details by address
    mapping(address depositor => BorrowerDetails) public borrowing;
    //Get external protocol deposit details by protocol name (enum)
    mapping(Protocol => ProtocolDeposit) public protocolDeposit;
    uint256 public totalVolumeOfBorrowersAmountinWei;
    //eth vault value
    uint256 public totalVolumeOfBorrowersAmountinUSD;
    uint128 public noOfBorrowers;
    uint256 public totalInterest;
    uint256 public totalInterestFromLiquidation;
    uint256 public abondAmintPool;
    uint256 public ethProfitsOfLiquidators;
    uint256 private interestFromExternalProtocolDuringLiquidation;

    //no of times deposited in external protocol(always 1 ahead) 
    uint64 public externalProtocolDepositCount;
    uint128 private PRECISION;
    uint256 private CUMULATIVE_PRECISION;

    // Eth depsoited in particular index
    mapping(uint256=>uint256) externalProtocolCountTotalValue;
    uint256 public amintGainedFromLiquidation;
    OmniChainTreasuryData public omniChainTreasury;//! omnichainTreasury contains global treasury data(all chains)
    using OptionsBuilder for bytes;
    uint32 private dstEid;

    function initialize(
        address _borrowing,
        address _tokenAddress,
        address _abondAddress,
        address _cdsContract,
        address _wethGateway,
        address _comet,
        address _aavePoolAddressProvider,
        address _aToken,
        address _usdt,
        address _weth,
        address _endpoint,
        address _delegate
        ) initializer public{
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __oAppinit(_endpoint, _delegate);
        borrowingContract = _borrowing;
        cdsContract = _cdsContract;
        borrow = IBorrowing(_borrowing);
        amint = IAMINT(_tokenAddress);
        abond = IABONDToken(_abondAddress);
        wethGateway = IWrappedTokenGatewayV3(_wethGateway);       // 0xD322A49006FC828F9B5B37Ab215F99B4E5caB19C
        comet = CometMainInterface(_comet);                    // 0xA17581A9E3356d9A858b789D68B4d866e593aE94
        WETH = IWETH9(_weth);                                  // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        aavePoolAddressProvider = IPoolAddressesProvider(_aavePoolAddressProvider);  // 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e
        aToken = IERC20(_aToken);                                                    // 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8
        aaveWETH = _wethGateway;
        usdt = IERC20(_usdt);
        externalProtocolDepositCount = 1;
        PRECISION = 1e18;
        CUMULATIVE_PRECISION = 1e27;
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override{}

    modifier onlyBorrowingContract() {
        require( msg.sender == borrowingContract, "This function can only called by borrowing contract");
        _;
    }

    modifier onlyCDSContract() {
        require( msg.sender == cdsContract, "This function can only called by CDS contract");
        _;
    }
    modifier onlyCDSOrBorrowingContract() {
        require( (msg.sender == cdsContract) || (msg.sender == borrowingContract), "This function can only called by Borrowing or CDS contract");
        _;
    }

    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    /**
     * @dev This function takes ethPrice, depositTime parameters to deposit eth into the contract and mint them back the AMINT tokens.
     * @param _ethPrice get current eth price 
     * @param _depositTime get unixtime stamp at the time of deposit
     **/

    function deposit(
        uint256 _depositingAmount,
        address user,
        uint128 _ethPrice,
        uint64 _depositTime
    ) external payable onlyBorrowingContract returns(DepositResult memory) {

        require (msg.value > _depositingAmount,"Treasury: Don't have enough LZ fee");

        uint64 borrowerIndex;
        //check if borrower is depositing for the first time or not
        if (!borrowing[user].hasDeposited) {
            //change borrowerindex to 1
            borrowerIndex = borrowing[user].borrowerIndex = 1;
          
            //change hasDeposited bool to true after first deposit
            borrowing[user].hasDeposited = true;
            ++noOfBorrowers;
            ++omniChainTreasury.noOfBorrowers;
        }
        else {
            //increment the borrowerIndex for each deposit
            borrowerIndex = ++borrowing[user].borrowerIndex;
            // borrowerIndex = borrowing[user].borrowerIndex;
        }
    
        // update total deposited amount of the user
        borrowing[user].depositedAmount += _depositingAmount;

        // update deposited amount of the user
        borrowing[user].depositDetails[borrowerIndex].depositedAmount = uint128(_depositingAmount);

        //Total volume of borrowers in USD
        totalVolumeOfBorrowersAmountinUSD += (_ethPrice * _depositingAmount);
        omniChainTreasury.totalVolumeOfBorrowersAmountinUSD += (_ethPrice * _depositingAmount);

        //Total volume of borrowers in Wei
        totalVolumeOfBorrowersAmountinWei += _depositingAmount;
        omniChainTreasury.totalVolumeOfBorrowersAmountinWei += _depositingAmount;

        //Adding depositTime to borrowing struct
        borrowing[user].depositDetails[borrowerIndex].depositedTime = _depositTime;

        //Adding ethprice to struct
        borrowing[user].depositDetails[borrowerIndex].ethPriceAtDeposit = _ethPrice;

        borrowing[user].depositDetails[borrowerIndex].depositedAmountUsdValue = uint128(_depositingAmount) * _ethPrice;
        
        //having the count of the deposit done to Aave/Compound in batched
        borrowing[user].depositDetails[borrowerIndex].externalProtocolCount = externalProtocolDepositCount;

        externalProtocolCountTotalValue[externalProtocolDepositCount] += ((_depositingAmount * 50)/100);

        uint256 externalProtocolDepositEth = ((_depositingAmount * 25)/100);

        // depositToAaveByUser(externalProtocolDepositEth);
        // depositToCompoundByUser(externalProtocolDepositEth);

        bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        //! calculting fee 
        MessagingFee memory fee = quote(dstEid, FunctionToDo(1), omniChainTreasury, AmintOftTransferData( address(0), 0), _options, false);

        //! Calling omnichain send function
        send(dstEid, FunctionToDo(1), omniChainTreasury, AmintOftTransferData( address(0), 0), fee, _options);

        emit Deposit(user,_depositingAmount);
        return DepositResult(borrowing[user].hasDeposited,borrowerIndex);
    }

    /**
     * @dev withdraw the deposited eth
     * @param borrower borrower address
     * @param toAddress adrress to return eth
     * @param _amount amount of eth to return
     * @param index deposit index
     */
    function withdraw(
        address borrower,
        address toAddress,
        uint256 _amount,
        uint64 index
    ) external payable onlyBorrowingContract returns(bool){
        // Check the _amount is non zero
        require(_amount > 0, "Cannot withdraw zero Ether");
        require(borrowing[borrower].depositDetails[index].withdrawed,"");
        uint256 amount = _amount;

        // Updating lastEthVaultValue in borrowing
        borrow.updateLastEthVaultValue(borrowing[borrower].depositDetails[index].depositedAmountUsdValue);
        // Updating total volumes
        totalVolumeOfBorrowersAmountinUSD -= borrowing[borrower].depositDetails[index].depositedAmountUsdValue;
        totalVolumeOfBorrowersAmountinWei -= amount * 2;
        omniChainTreasury.totalVolumeOfBorrowersAmountinUSD -= borrowing[borrower].depositDetails[index].depositedAmountUsdValue;
        omniChainTreasury.totalVolumeOfBorrowersAmountinWei -= amount * 2;

        // Deduct tototalBorrowedAmountt
        borrowing[borrower].totalBorrowedAmount -= borrowing[borrower].depositDetails[index].borrowedAmount;
        borrowing[borrower].depositDetails[index].depositedAmount = 0;

        if(borrowing[borrower].depositedAmount == 0){
            --noOfBorrowers;
            --omniChainTreasury.noOfBorrowers;
        }
        borrowing[borrower].depositDetails[index].withdrawAmount += uint128(amount);
        bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        //! calculting fee 
        MessagingFee memory fee = quote(dstEid, FunctionToDo(1), omniChainTreasury, AmintOftTransferData( address(0), 0), _options, false);

        //! Calling omnichain send function
        send(dstEid, FunctionToDo(1), omniChainTreasury, AmintOftTransferData( address(0), 0), fee, _options);
        // Send the ETH to Borrower
        (bool sent,) = payable(toAddress).call{value: amount}("");
        require(sent, "Failed to send Ether");

        emit Withdraw(toAddress,_amount);
        return true;
    }

    function withdrawFromExternalProtocol(address user, uint128 aBondAmount) external onlyBorrowingContract returns(uint256){

        uint256 aTokenBalance = aToken.balanceOf(address(this));
        _calculateCumulativeRate(aTokenBalance, Protocol.Aave);

        uint256 cETHBalance = comet.balanceOf(address(this));
        _calculateCumulativeRate(cETHBalance, Protocol.Compound);

        uint256 redeemAmount = withdrawFromAaveByUser(user,aBondAmount) + withdrawFromCompoundByUser(user,aBondAmount);
        // Send the ETH to user
        (bool sent,) = payable(user).call{value: redeemAmount}("");
        require(sent, "Failed to send Ether");
        return redeemAmount;
    }

    // //to increase the global external protocol count.
    // function increaseExternalProtocolCount() external {
    //     uint64 aaveDepositIndex = protocolDeposit[Protocol.Aave].depositIndex;
    //     uint64 compoundDepositIndex = protocolDeposit[Protocol.Compound].depositIndex;
    //     externalProtocolDepositCount = aaveDepositIndex > compoundDepositIndex ? aaveDepositIndex : compoundDepositIndex;
    // }

    /**
     * @dev This function depsoit 25% of the deposited ETH to AAVE and mint aTokens 
    */

    // function depositToAave() external onlyBorrowingContract{

    //     //Divide the Total ETH in the contract to 1/4
    //     uint256 share = (externalProtocolCountTotalValue[externalProtocolDepositCount]*50)/100;

    //     //Check the amount to be deposited is greater than zero
    //     if(share == 0){
    //         revert Treasury_ZeroDeposit();
    //     }

    //     address poolAddress = aavePoolAddressProvider.getLendingPool();

    //     if(poolAddress == address(0)){
    //         revert Treasury_AavePoolAddressZero();
    //     }

    //     //Atoken balance before depsoit
    //     uint256 aTokenBeforeDeposit = aToken.balanceOf(address(this));

    //     // Call the deposit function in aave to deposit eth.
    //     wethGateway.depositETH{value: share}(poolAddress,address(this),0);

    //     uint256 creditedAmount = aToken.balanceOf(address(this));
    //     if(creditedAmount == protocolDeposit[Protocol.Aave].totalCreditedTokens){
    //         revert Treasury_AaveDepositAndMintFailed();
    //     }

    //     uint64 count = protocolDeposit[Protocol.Aave].depositIndex;
    //     count += 1;

    //     externalProtocolDepositCount++;

    //     // If it's the first deposit, set the cumulative rate to precision (i.e., 1 in fixed-point representation).
    //     if (count == 1 || protocolDeposit[Protocol.Aave].totalCreditedTokens == 0) {
    //         protocolDeposit[Protocol.Aave].cumulativeRate = CUMULATIVE_PRECISION; 
    //     } else {
    //         // Calculate the change in the credited amount relative to the total credited tokens so far.
    //         uint256 change = (aTokenBeforeDeposit - protocolDeposit[Protocol.Aave].totalCreditedTokens) * CUMULATIVE_PRECISION / protocolDeposit[Protocol.Aave].totalCreditedTokens;
    //         // Update the cumulative rate using the calculated change.
    //         protocolDeposit[Protocol.Aave].cumulativeRate = ((CUMULATIVE_PRECISION + change) * protocolDeposit[Protocol.Aave].cumulativeRate) / CUMULATIVE_PRECISION;
    //     }
    //     // Compute the discounted price of the deposit using the cumulative rate.
    //     protocolDeposit[Protocol.Aave].eachDepositToProtocol[count].discountedPrice = share * CUMULATIVE_PRECISION / protocolDeposit[Protocol.Aave].cumulativeRate;

    //     //Assign depositIndex(number of times deposited)
    //     protocolDeposit[Protocol.Aave].depositIndex = count;

    //     //Update the total amount deposited in Aave
    //     protocolDeposit[Protocol.Aave].depositedAmount += share;

    //     //Update the deposited time
    //     protocolDeposit[Protocol.Aave].eachDepositToProtocol[count].depositedTime = uint64(block.timestamp);

    //     //Update the deposited amount
    //     protocolDeposit[Protocol.Aave].eachDepositToProtocol[count].depositedAmount = uint128(share);

    //     //Update the deposited amount in USD
    //     uint128 ethPrice = protocolDeposit[Protocol.Aave].eachDepositToProtocol[count].ethPriceAtDeposit = uint128(borrow.getUSDValue());
    //     protocolDeposit[Protocol.Aave].eachDepositToProtocol[count].depositedUsdValue = share * ethPrice;

    //     //Update the total deposited amount in USD
    //     protocolDeposit[Protocol.Aave].depositedUsdValue = protocolDeposit[Protocol.Aave].depositedAmount * ethPrice;

    //     protocolDeposit[Protocol.Aave].eachDepositToProtocol[count].tokensCredited = uint128(creditedAmount) - uint128(protocolDeposit[Protocol.Aave].totalCreditedTokens);
    //     protocolDeposit[Protocol.Aave].totalCreditedTokens = creditedAmount;

    //     emit DepositToAave(count,share);
    // }

    /**
    * @dev Calculates the interest for a particular deposit based on its count for Aave.
    * @param count The deposit index (or count) for which the interest needs to be calculated.
    * @return interestValue The computed interest amount for the specified deposit.
    */

    //! have valid names for input parameters
    // function calculateInterestForDepositAave(uint64 count) public view returns (uint256) {
        
    //     // Ensure the provided count is within valid range
    //     if(count > protocolDeposit[Protocol.Aave].depositIndex || count == 0) {
    //         revert("Invalid count provided");
    //     }

    //     // Get the current credited amount from aToken
    //     uint256 creditedAmount = aToken.balanceOf(address(this));

    //     // Calculate the change rate based on the difference between the current credited amount and the total credited tokens 
    //     uint256 change = (creditedAmount - protocolDeposit[Protocol.Aave].totalCreditedTokens) * CUMULATIVE_PRECISION / protocolDeposit[Protocol.Aave].totalCreditedTokens;

    //     // Compute the current cumulative rate using the change and the stored cumulative rate
    //     uint256 currentCumulativeRate = (CUMULATIVE_PRECISION + change) * protocolDeposit[Protocol.Aave].cumulativeRate / CUMULATIVE_PRECISION;
        
    //     // Calculate the present value of the deposit using the current cumulative rate and the stored discounted price for the deposit
    //     uint256 presentValue = currentCumulativeRate * protocolDeposit[Protocol.Aave].eachDepositToProtocol[count].discountedPrice / CUMULATIVE_PRECISION;

    //     // Compute the interest by subtracting the original deposited amount from the present value
    //     uint256 interestValue = presentValue - protocolDeposit[Protocol.Aave].eachDepositToProtocol[count].depositedAmount;
        
    //     // Return the computed interest value
    //     return interestValue;
    // }

    /**
     * @dev This function withdraw ETH from AAVE.
     * @param index index of aave deposit 
     */

    // function withdrawFromAave(uint64 index) external onlyBorrowingContract{

    //     //Check the deposited amount in the given index is already withdrawed
    //     require(!protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].withdrawed,"Already withdrawed in this index");
    //     uint256 creditedAmount = aToken.balanceOf(address(this));
    //     // Calculate the change rate based on the difference between the current credited amount and the total credited tokens 
    //     uint256 change = (creditedAmount - protocolDeposit[Protocol.Aave].totalCreditedTokens) * CUMULATIVE_PRECISION / protocolDeposit[Protocol.Aave].totalCreditedTokens;

    //     // Compute the current cumulative rate using the change and the stored cumulative rate
    //     uint256 currentCumulativeRate = (CUMULATIVE_PRECISION + change) * protocolDeposit[Protocol.Aave].cumulativeRate / CUMULATIVE_PRECISION;
    //     protocolDeposit[Protocol.Aave].cumulativeRate = currentCumulativeRate;
    //     //withdraw amount
    //     uint256 amount = (currentCumulativeRate * protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].discountedPrice)/CUMULATIVE_PRECISION;
    //     address poolAddress = aavePoolAddressProvider.getLendingPool();

    //     if(poolAddress == address(0)){
    //         revert Treasury_AavePoolAddressZero();
    //     }

    //     aToken.approve(aaveWETH,amount);
    //     protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].interestGained = uint128(amount) - protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].depositedAmount;

    //     // Call the withdraw function in aave to withdraw eth.
    //     wethGateway.withdrawETH(poolAddress,amount,address(this));

    //     uint256 aaveToken = aToken.balanceOf(address(this));
    //     if(aaveToken == protocolDeposit[Protocol.Aave].totalCreditedTokens){
    //         revert Treasury_AaveWithdrawFailed();
    //     }

    //     //Update the total amount deposited in Aave
    //     //protocolDeposit[Protocol.Aave].depositedAmount -= amount;

    //     //Set withdrawed to true
    //     protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].withdrawed = true;

    //     //Update the withdraw time
    //     protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].withdrawTime = uint64(block.timestamp);

    //     //Update the withdrawed amount in USD
    //     uint128 ethPrice = protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].ethPriceAtWithdraw = uint64(borrow.getUSDValue());
    //     protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].withdrawedUsdValue = amount * ethPrice;

    //     //Update the total deposited amount in USD
    //     protocolDeposit[Protocol.Aave].depositedUsdValue = protocolDeposit[Protocol.Aave].depositedAmount * ethPrice;
    //     //! why we are updating deposited value

    //     protocolDeposit[Protocol.Aave].totalCreditedTokens = aaveToken; 

    //     emit WithdrawFromAave(index,amount);
    // }

    /**
     * @dev This function depsoit 25% of the deposited ETH to COMPOUND and mint cETH. 
    */

    // function depositToCompound() external onlyBorrowingContract{

    //     //Divide the Total ETH in the contract to 1/4
    //     uint256 share = (externalProtocolCountTotalValue[externalProtocolDepositCount - 1]*50)/100;

    //     //Check the amount to be deposited is greater than zero       
    //     if(share == 0){
    //         revert Treasury_ZeroDeposit();
    //     }

    //     // Call the deposit function in Coumpound to deposit eth.
    //     comet.mint{value: share}();

    //     uint256 creditedAmount = comet.balanceOf(address(this));

    //     if(creditedAmount == protocolDeposit[Protocol.Compound].totalCreditedTokens){
    //         revert Treasury_CompoundDepositAndMintFailed();
    //     }

    //     uint64 count = protocolDeposit[Protocol.Compound].depositIndex;
    //     count += 1;

    //     //Assign depositIndex(number of times deposited)
    //     protocolDeposit[Protocol.Compound].depositIndex = count;

    //     //Update the total amount deposited in Compound
    //     protocolDeposit[Protocol.Compound].depositedAmount += share;

    //     //Update the deposited time
    //     protocolDeposit[Protocol.Compound].eachDepositToProtocol[count].depositedTime = uint64(block.timestamp);

    //     //Update the deposited amount
    //     protocolDeposit[Protocol.Compound].eachDepositToProtocol[count].depositedAmount = uint128(share);

    //     //Update the deposited amount in USD
    //     uint128 ethPrice = protocolDeposit[Protocol.Compound].eachDepositToProtocol[count].ethPriceAtDeposit = uint128(borrow.getUSDValue());
    //     protocolDeposit[Protocol.Compound].eachDepositToProtocol[count].depositedUsdValue = share * ethPrice;

    //     //Update the total deposited amount in USD
    //     protocolDeposit[Protocol.Compound].depositedUsdValue = protocolDeposit[Protocol.Compound].depositedAmount * ethPrice;

    //     protocolDeposit[Protocol.Compound].eachDepositToProtocol[count].tokensCredited = uint128(creditedAmount) - uint128(protocolDeposit[Protocol.Compound].totalCreditedTokens);
    //     protocolDeposit[Protocol.Compound].totalCreditedTokens = creditedAmount;

    //     emit DepositToCompound(count,share);
    // }

    /**
     * @dev This function withdraw ETH from COMPOUND.
     */

    // function withdrawFromCompound(uint64 index) external onlyBorrowingContract{

    //     uint256 amount = protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].tokensCredited;

    //     //Check the deposited amount in the given index is already withdrawed
    //     require(!protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].withdrawed,"Already withdrawed in this index");

    //     //Check the amount to be withdraw is greater than zero
    //     if(amount == 0){
    //         revert Treasury_ZeroWithdraw();
    //     }

    //     // Call the redeem function in Compound to withdraw eth.
    //     comet.redeem(amount);
    //     uint256 cToken = comet.balanceOf(address(this));
    //     if(cToken == protocolDeposit[Protocol.Compound].totalCreditedTokens){
    //         revert Treasury_CompoundWithdrawFailed();
    //     }

    //     //Update the total amount deposited in Coumpound
    //     protocolDeposit[Protocol.Compound].depositedAmount -= amount;

    //     //Set withdrawed to true
    //     protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].withdrawed = true;

    //     //Update the withdraw time
    //     protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].withdrawTime = uint64(block.timestamp);

    //     //Update the withdraw amount in USD
    //     uint128 ethPrice = protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].ethPriceAtWithdraw = uint128(borrow.getUSDValue());
    //     protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].withdrawedUsdValue = amount * ethPrice;

    //     //Update the total deposited amount in USD
    //     protocolDeposit[Protocol.Compound].depositedUsdValue = protocolDeposit[Protocol.Compound].depositedAmount * ethPrice;

    //     protocolDeposit[Protocol.Compound].totalCreditedTokens -= amount;
    //     // protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].interestGained = uint128(getInterestForCompoundDeposit(index));
    //     protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].tokensCredited = 0;

    //     emit WithdrawFromCompound(index,amount);
    // }

    /**
    * @dev Calculates the accrued interest for a specific deposit based on the cTokens credited.
    *
    * The function retrieves the deposit details for the given count and determines
    * the interest accrued by comparing the equivalent ETH value of the cTokens at the
    * current exchange rate with the original deposited ETH amount.
    *
    * Interest = ((cTokens credited * current exchange rate) / scaling factor) - original deposited ETH
    *
    * @param depositor The deposit index/count for which the interest needs to be calculated.
    * @return The accrued interest for the specified deposit.
    */
    // function getInterestForCompoundDeposit(address depositor,uint64 index) public returns (uint256) {
    //     // Retrieve the deposit details for the specified count
    //     DepositDetails memory depositDetails = borrowing[depositor].depositDetails[index];
        
    //     // Obtain the current exchange rate from the Compound protocol
    //     uint256 currentExchangeRate = comet.exchangeRateCurrent();
        
    //     // Compute the equivalent ETH value of the cTokens at the current exchange rate
    //     // Taking into account the fixed-point arithmetic (scaling factor of 1e18)
    //     uint256 currentEquivalentEth = (depositDetails.cTokensCredited * currentExchangeRate) / PRECISION;

    //     // Calculate the accrued interest by subtracting the original deposited ETH 
    //     // amount from the current equivalent ETH value
    //     return currentEquivalentEth - ((depositDetails.depositedAmount * 25)/100);
    // }

    /**
     * calculates the interest gained by user from External protocol deposits
     */
    // function totalInterestFromExternalProtocol(address depositor, uint64 index) external view returns(uint256){
    //     uint64 count = borrowing[depositor].depositDetails[index].externalProtocolCount;
    //     uint256 interestGainedByUser;

    //     for(uint64 i = count;i < externalProtocolDepositCount;i++){

    //         EachDepositToProtocol memory aaveDeposit = protocolDeposit[Protocol.Aave].eachDepositToProtocol[i];
    //         EachDepositToProtocol memory compoundDeposit = protocolDeposit[Protocol.Compound].eachDepositToProtocol[i];

    //         if(i==1 || protocolDeposit[Protocol.Aave].eachDepositToProtocol[i-1].withdrawed){

    //             uint256 totalValue = (externalProtocolCountTotalValue[i] * 50)/100;
    //             uint256 currentValue = (borrowing[depositor].depositDetails[index].depositedAmount * 25)/100;
    //             uint256 totalInterestFromExtPro;

    //             if(aaveDeposit.withdrawed){
    //                 totalInterestFromExtPro += aaveDeposit.interestGained;
    //             }else{
    //                 totalInterestFromExtPro += calculateInterestForDepositAave(i);
    //             }

    //             uint256 ratio = ((currentValue * PRECISION)/totalValue);
    //             interestGainedByUser += ((ratio*totalInterestFromExtPro)/PRECISION);

    //         }
    //         if(i==1 || protocolDeposit[Protocol.Compound].eachDepositToProtocol[i-1].withdrawed){

    //             uint256 totalValue = (externalProtocolCountTotalValue[i] * 50)/100;
    //             uint256 currentValue = (borrowing[depositor].depositDetails[index].depositedAmount * 25)/100;
    //             uint256 totalInterestFromExtPro;

    //             if(compoundDeposit.withdrawed){
    //                 totalInterestFromExtPro += compoundDeposit.interestGained;
    //             }else{
    //                 // totalInterestFromExtPro += getInterestForCompoundDeposit(i);
    //             }

    //             uint256 ratio = ((currentValue * PRECISION)/totalValue);
    //             interestGainedByUser += ((ratio*totalInterestFromExtPro)/PRECISION);
    //         }

    //     }

    //     return interestGainedByUser;
    // }

    function calculateYieldsForExternalProtocol(address user,uint128 aBondAmount) external view onlyBorrowingContract returns (uint256) {
        
        State memory userState = abond.userStates(user);

        uint128 depositedAmount = (aBondAmount * userState.ethBacked)/PRECISION;
        uint256 normalizedAmount = (depositedAmount * CUMULATIVE_PRECISION)/userState.cumulativeRate;

        uint256 currentCumulativeRateAave = getCurrentCumulativeRate(aToken.balanceOf(address(this)),Protocol.Aave);
        uint256 currentCumulativeRateComp = getCurrentCumulativeRate(comet.balanceOf(address(this)),Protocol.Compound);

        uint256 currentCumulativeRate = currentCumulativeRateAave < currentCumulativeRateComp ? currentCumulativeRateAave : currentCumulativeRateComp;
        //withdraw amount
        uint256 amount = (currentCumulativeRate * normalizedAmount)/CUMULATIVE_PRECISION;
        
        return amount;
    }

    function getCurrentCumulativeRate(uint256 balanceBeforeEvent, Protocol _protocol) internal view returns (uint256){
        uint256 currentCumulativeRate;
        // If it's the first deposit, set the cumulative rate to precision (i.e., 1 in fixed-point representation).
        if (protocolDeposit[_protocol].totalCreditedTokens == 0) {
            currentCumulativeRate = CUMULATIVE_PRECISION;
        } else {
            // Calculate the change in the credited amount relative to the total credited tokens so far.
            uint256 change = (balanceBeforeEvent - protocolDeposit[_protocol].totalCreditedTokens) * CUMULATIVE_PRECISION / protocolDeposit[_protocol].totalCreditedTokens;
            // Update the cumulative rate using the calculated change.
            currentCumulativeRate = ((CUMULATIVE_PRECISION + change) * protocolDeposit[_protocol].cumulativeRate) / CUMULATIVE_PRECISION;
        }
        return currentCumulativeRate;
    }

    function getBalanceInTreasury() external view returns(uint256){
        return address(this).balance;
    }

    function updateDepositDetails(
        address depositor,
        uint64 index,DepositDetails memory depositDetail
    ) external onlyBorrowingContract{
            borrowing[depositor].depositDetails[index] = depositDetail;
    }

    function updateHasBorrowed(address borrower,bool _bool) external onlyBorrowingContract{
        borrowing[borrower].hasBorrowed = _bool;
    }
    function updateTotalDepositedAmount(address borrower,uint128 amount) external onlyBorrowingContract{
        borrowing[borrower].depositedAmount -= amount;
    }
    function updateTotalBorrowedAmount(address borrower,uint256 amount) external onlyBorrowingContract{
        borrowing[borrower].totalBorrowedAmount += amount;
    }

    function updateTotalInterest(uint256 _amount) external onlyBorrowingContract{
        totalInterest += _amount;
        omniChainTreasury.totalInterest += _amount;
    }

    function updateTotalInterestFromLiquidation(uint256 _amount) external onlyBorrowingContract{
        totalInterestFromLiquidation += _amount;
        omniChainTreasury.totalInterestFromLiquidation += _amount;
    }

    function updateAbondAmintPool(uint256 amount,bool operation) external onlyBorrowingContract{
        require(amount != 0, "Treasury:Amount should not be zero");
        if(operation){
            abondAmintPool += amount;
            omniChainTreasury.abondAmintPool += amount;
        }else{
            abondAmintPool -= amount;
            omniChainTreasury.abondAmintPool -= amount;
        }
    }

    function updateAmintGainedFromLiquidation(uint256 amount,bool operation) external onlyBorrowingContract{
        if(operation){
            amintGainedFromLiquidation += amount;
            omniChainTreasury.amintGainedFromLiquidation += amount;
        }else{
            amintGainedFromLiquidation -= amount;
            omniChainTreasury.amintGainedFromLiquidation -= amount;
        }
    }

    function updateEthProfitsOfLiquidators(uint256 amount,bool operation) external onlyCDSOrBorrowingContract{
        require(amount != 0, "Treasury:Amount should not be zero");
        if(operation){
            ethProfitsOfLiquidators += amount;
            omniChainTreasury.ethProfitsOfLiquidators += amount;

        }else{
            ethProfitsOfLiquidators -= amount;
            omniChainTreasury.ethProfitsOfLiquidators += amount;
        }
    }

    function updateInterestFromExternalProtocol(uint256 amount) external onlyBorrowingContract{
        interestFromExternalProtocolDuringLiquidation += amount;
        omniChainTreasury.interestFromExternalProtocolDuringLiquidation += amount;
    }

    function getBorrowing(address depositor,uint64 index) external view returns(GetBorrowingResult memory){
        return GetBorrowingResult(
            borrowing[depositor].borrowerIndex,
            borrowing[depositor].depositDetails[index]);
    }

    function omniChainTreasuryNoOfBorrowers() external view returns(uint128){
        return omniChainTreasury.noOfBorrowers;
    }

    function omniChainTreasuryTotalVolumeOfBorrowersAmountinWei() external view returns(uint256){
        return omniChainTreasury.totalVolumeOfBorrowersAmountinWei;
    }

    function omniChainTreasuryTotalVolumeOfBorrowersAmountinUSD() external view returns(uint256){
        return omniChainTreasury.totalVolumeOfBorrowersAmountinUSD;
    }

    function omniChainTreasuryEthProfitsOfLiquidators() external view returns(uint256){
        return omniChainTreasury.ethProfitsOfLiquidators;
    }

    function getAaveCumulativeRate() private view returns(uint128){
        return uint128(protocolDeposit[Protocol.Aave].cumulativeRate);
    }

    function getCompoundCumulativeRate() private view returns(uint128){
        return uint128(protocolDeposit[Protocol.Compound].cumulativeRate);
    }

    function getExternalProtocolCumulativeRate(bool maximum) public view onlyBorrowingContract returns(uint128){
        uint128 aaveCumulativeRate = getAaveCumulativeRate();
        uint128 compoundCumulativeRate = getCompoundCumulativeRate();
        if(maximum){
            if(aaveCumulativeRate > compoundCumulativeRate){
                return aaveCumulativeRate;
            }else{
                return compoundCumulativeRate;
            }
        }else{
            if(aaveCumulativeRate < compoundCumulativeRate){
                return aaveCumulativeRate;
            }else{
                return compoundCumulativeRate;
            }
        }
    }

    /**
     * amint approval
     * @param _address address to spend
     * @param _amount amint amount
     */
    function approveAmint(address _address, uint _amount) external onlyCDSOrBorrowingContract{
        require(_address != address(0) && _amount != 0, "Input address or amount is invalid");
        bool state = amint.approve(_address, _amount);
        require(state == true, "Approve failed");
    }

    /**
     * usdt approval
     */
    function approveUsdt(address _address, uint _amount) external onlyCDSContract{
        require(_address != address(0) && _amount != 0, "Input address or amount is invalid");
        bool state = usdt.approve(_address, _amount);
        require(state == true, "Approve failed");
    }

    /**
     * @dev This function withdraw interest.
     * @param toAddress The address to whom to transfer StableCoins.
     * @param amount The amount of stablecoins to withdraw.
     */

    function withdrawInterest(address toAddress,uint256 amount) external onlyOwner{
        require(toAddress != address(0) && amount != 0, "Input address or amount is invalid");
        require(amount <= (totalInterest + totalInterestFromLiquidation),"Treasury don't have enough interest");
        totalInterest -= amount;
        bool sent = amint.transfer(toAddress,amount);
        require(sent, "Failed to send Ether");
    }

    /**
     * transfer eth from treasury
     */
    function transferEthToCdsLiquidators(address borrower,uint128 amount) external onlyCDSContract{
        require(borrower != address(0) && amount != 0, "Input address or amount is invalid");
        require(amount <= ethProfitsOfLiquidators,"Treasury don't have enough ETH amount");
        ethProfitsOfLiquidators -= amount;
        (bool sent,) = payable(borrower).call{value: amount}("");
        if(!sent){
            revert Treasury_EthTransferToCdsLiquidatorFailed();
        }
    }

    function withdrawExternalProtocolInterest(address toAddress,uint128 amount) external onlyOwner{
        require(toAddress != address(0) && amount != 0, "Input address or amount is invalid");
        require(amount <= interestFromExternalProtocolDuringLiquidation,"Treasury don't have enough interest amount");
        interestFromExternalProtocolDuringLiquidation -= amount;
        (bool sent,) = payable(toAddress).call{value: amount}("");
        if(!sent){
            revert Treasury_WithdrawExternalProtocolInterestFailed();
        }
    }

    function _calculateCumulativeRate(uint256 balanceBeforeEvent, Protocol _protocol) internal returns(uint256){
        uint256 currentCumulativeRate;
        // If it's the first deposit, set the cumulative rate to precision (i.e., 1 in fixed-point representation).
        if (protocolDeposit[_protocol].totalCreditedTokens == 0) {
            currentCumulativeRate = CUMULATIVE_PRECISION;
        } else {
            // Calculate the change in the credited amount relative to the total credited tokens so far.
            uint256 change = (balanceBeforeEvent - protocolDeposit[_protocol].totalCreditedTokens) * CUMULATIVE_PRECISION / protocolDeposit[_protocol].totalCreditedTokens;
            // Update the cumulative rate using the calculated change.
            currentCumulativeRate = ((CUMULATIVE_PRECISION + change) * protocolDeposit[_protocol].cumulativeRate) / CUMULATIVE_PRECISION;
        }
        protocolDeposit[_protocol].cumulativeRate = currentCumulativeRate;
        return currentCumulativeRate;
    }

    function depositToAaveByUser(uint256 depositAmount) internal onlyBorrowingContract{
        //Atoken balance before depsoit
        uint256 aTokenBeforeDeposit = aToken.balanceOf(address(this));

        _calculateCumulativeRate(aTokenBeforeDeposit, Protocol.Aave);

        address poolAddress = aavePoolAddressProvider.getPool();

        if(poolAddress == address(0)){
            revert Treasury_AavePoolAddressZero();
        }

        wethGateway.depositETH{value: depositAmount}(poolAddress,address(this),0);
        uint256 creditedAmount = aToken.balanceOf(address(this));
        protocolDeposit[Protocol.Aave].totalCreditedTokens = creditedAmount;
    }

    function depositToCompoundByUser(uint256 depositAmount) internal onlyBorrowingContract {
        //Ctoken balance before depsoit
        uint256 cTokenBeforeDeposit = comet.balanceOf(address(this));

        _calculateCumulativeRate(cTokenBeforeDeposit, Protocol.Compound);

        // Changing ETH into WETH
        WETH.deposit{value: depositAmount}();

        // Approve WETH to Comet
        WETH.approve(address(comet), depositAmount);

        // Call the deposit function in Coumpound to deposit eth.
        comet.supply(address(WETH), depositAmount);

        uint256 creditedAmount = comet.balanceOf(address(this));

        protocolDeposit[Protocol.Compound].totalCreditedTokens = creditedAmount;

    }

    function withdrawFromAaveByUser(address user,uint128 aBondAmount) internal returns(uint256){
        State memory userState = abond.userStates(user);
        uint128 depositedAmount = (aBondAmount * userState.ethBacked)/PRECISION;
        uint256 normalizedAmount = (depositedAmount * CUMULATIVE_PRECISION * 50)/ (userState.cumulativeRate * 100);
        
        //withdraw amount
        uint256 amount = (getExternalProtocolCumulativeRate(false) * normalizedAmount)/CUMULATIVE_PRECISION;

        address poolAddress = aavePoolAddressProvider.getPool();

        if(poolAddress == address(0)){
            revert Treasury_AavePoolAddressZero();
        }

        aToken.approve(aaveWETH,amount);

        // Call the withdraw function in aave to withdraw eth.
        wethGateway.withdrawETH(poolAddress,amount,address(this));

        protocolDeposit[Protocol.Aave].totalCreditedTokens = aToken.balanceOf(address(this));
        return amount;
    }

    function withdrawFromCompoundByUser(address user,uint128 aBondAmount) internal returns(uint256){
        State memory userState = abond.userStates(user);
        uint128 depositedAmount = (aBondAmount * userState.ethBacked)/PRECISION;
        uint256 normalizedAmount = (depositedAmount * CUMULATIVE_PRECISION * 50)/ (userState.cumulativeRate * 100);

        //withdraw amount
        uint256 amount = (getExternalProtocolCumulativeRate(false) * normalizedAmount)/CUMULATIVE_PRECISION;

        comet.withdraw(address(WETH), amount);

        protocolDeposit[Protocol.Compound].totalCreditedTokens = comet.balanceOf(address(this));

        WETH.withdraw(amount);
        return amount;
    }

    function setDstEid(uint32 _eid) external onlyOwner{
        require(_eid != 0, "EID can't be zero");
        dstEid = _eid;
    }

    function oftReceiveFromOtherChains(
        FunctionToDo _functionToDo,
        AmintOftTransferData memory _oftTransferData
    ) external payable onlyCDSContract returns (MessagingReceipt memory receipt) {
        bytes memory _payload = abi.encode(_functionToDo, omniChainTreasury, _oftTransferData);

        //! getting options since,the src don't know the dst state
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(60000, 0);

        SendParam memory _sendParam = SendParam(
            dstEid,
            bytes32(uint256(uint160(_oftTransferData.recipient))),
            _oftTransferData.tokensToSend,
            _oftTransferData.tokensToSend,
            options,
            '0x',
            '0x'
        );
        MessagingFee memory fee = amint.quoteSend( _sendParam, false);

        bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250000, 0).addExecutorNativeDropOption(
            uint128(fee.nativeFee), 
            bytes32(uint256(uint160(0x7a2088a1bFc9d81c55368AE168C2C02570cB814F)))
        );

        MessagingFee memory _fee = quote(
            dstEid, FunctionToDo(1),
            omniChainTreasury,
            AmintOftTransferData( address(0), 0),
            _options,
            false);
        //! Calling layer zero send function to send to dst chain
        receipt = _lzSend(dstEid, _payload, _options, _fee, payable(msg.sender));
    }

    function send(
        uint32 _dstEid,
        FunctionToDo _functionToDo,
        OmniChainTreasuryData memory _message,
        AmintOftTransferData memory _oftTransferData,
        MessagingFee memory _fee,
        bytes memory _options
    ) internal onlyBorrowingContract returns (MessagingReceipt memory receipt) {
        bytes memory _payload = abi.encode(_functionToDo, _message, _oftTransferData);
        
        //! Calling layer zero send function to send to dst chain
        receipt = _lzSend(_dstEid, _payload, _options, _fee, payable(msg.sender));
    }

    function quote(
        uint32 _dstEid,
        FunctionToDo _functionToDo,
        OmniChainTreasuryData memory _message,
        AmintOftTransferData memory _oftTransferData,
        bytes memory _options,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(_functionToDo, _message, _oftTransferData);
        fee = _quote(_dstEid, payload, _options, _payInLzToken);
    }

    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {

        OmniChainTreasuryData memory data;
        FunctionToDo functionToDo;
        AmintOftTransferData memory oftTransferData;

        (functionToDo, data, oftTransferData) = abi.decode(payload, ( FunctionToDo, OmniChainTreasuryData, AmintOftTransferData));

        if(functionToDo == FunctionToDo.TRANSFER){

            //! getting options since,the src don't know the dst state
            bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(60000, 0);

            SendParam memory _sendParam = SendParam(
                dstEid,
                bytes32(uint256(uint160(oftTransferData.recipient))),
                oftTransferData.tokensToSend,
                oftTransferData.tokensToSend,
                _options,
                '0x',
                '0x'
            );
            MessagingFee memory _fee = amint.quoteSend( _sendParam, false);

            amint.send{ value: _fee.nativeFee}( _sendParam, _fee, address(this));

        }else{
            omniChainTreasury = data;
        }

    }

    receive() external payable{}
}