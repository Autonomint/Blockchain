// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interface/CDSInterface.sol";
import "../interface/IBorrowing.sol";
import "../interface/IAmint.sol";
import { State, IABONDToken } from "../interface/IAbond.sol";
import { BorrowLib } from "../lib/BorrowLib.sol";
import "../interface/ITreasury.sol";
import "../interface/IOptions.sol";
import "../interface/IMultiSign.sol";
import "hardhat/console.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

contract BorrowingTest is IBorrowing,Initializable,UUPSUpgradeable,ReentrancyGuardUpgradeable,OApp {

    IAMINT  private amint; // our stablecoin
    CDSInterface    private cds;
    IABONDToken private abond; // abond stablecoin
    ITreasury   private treasury;
    IOptions    private options; // options contract interface
    IMultiSign  private multiSign;
    uint256 private _downSideProtectionLimit;
    

    address private treasuryAddress; // treasury contract address
    address private admin; // admin address
    uint8   private LTV; // LTV is a percentage eg LTV = 60 is 60%, must be divided by 100 in calculations
    uint8   public APY; 
    uint256 public totalNormalizedAmount; // total normalized amount in protocol
    address public priceFeedAddress; // ETH USD pricefeed address
    uint128 private lastEthprice; // previous eth price
    uint256 public lastEthVaultValue; // previous eth vault value
    uint256 public lastCDSPoolValue; // previous CDS pool value
    uint256 private lastTotalCDSPool;
    uint256 public lastCumulativeRate; // previous cumulative rate
    uint128 private lastEventTime;
    uint128 public noOfLiquidations; // total number of liquidation happened till now
    uint64  private withdrawTimeLimit; // withdraw time limit
    uint128 public ratePerSec;
    uint64  private bondRatio;

    string  public constant name = "AMINT Stablecoin";
    string  public constant version = "1";
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address holder,address spender,uint256 allowedAmount,bool allowed,uint256 expiry)");

    uint256 public ethRemainingInWithdraw;
    uint256 public ethValueRemainingInWithdraw;

    uint32 private dstEid; //! dst id
    uint64 private nonce; 
    using OptionsBuilder for bytes;
    OmniChainBorrowingData public omniChainBorrowing; //! omniChainBorrowing contains global borrowing data(all chains)


    function initialize( 
        address _tokenAddress,
        address _cds,
        address _abondToken,
        address _multiSign,
        address _priceFeedAddress,
        uint64 chainId,
        address _endpoint,
        address _delegate
        ) initializer public{
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __oAppinit(_endpoint, _delegate);
        amint = IAMINT(_tokenAddress);
        cds = CDSInterface(_cds);
        abond = IABONDToken(_abondToken);
        multiSign = IMultiSign(_multiSign);
        priceFeedAddress = _priceFeedAddress;                       //0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint64 chainId,address verifyingContract)"),
            keccak256(bytes(name)),
            keccak256(bytes(version)),
            chainId,
            address(this)
        ));
        lastEthprice = uint128(getUSDValue());
        lastEventTime = uint128(block.timestamp);
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override{}

    modifier onlyAdmin(){
        require(msg.sender == admin,"Caller is not an admin");
        _;
    }
    modifier onlyTreasury(){
        require(msg.sender == treasuryAddress,"Function should only be called by treasury");
        _;
    }

    modifier whenNotPaused(IMultiSign.Functions _function) {
        require(!multiSign.functionState(_function),"Paused");
        _;
    }

    // Function to check if an address is a contract
    function isContract(address addr) public view returns (bool) {
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

    function setTreasury(address _treasury) external onlyAdmin{
        require(_treasury != address(0) && isContract(_treasury) != false, "Treasury must be contract address & can't be zero address");
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(6)));
        treasury = ITreasury(_treasury);
        treasuryAddress = _treasury;
    }

    /**
     * @dev set Options contract
     * @param _options option contract address
     */
    function setOptions(address _options) external onlyAdmin{
        require(_options != address(0) && isContract(_options) != false, "Options must be contract address & can't be zero address");
        options = IOptions(_options);
    }

    /**
     * @dev set admin address
     * @param _admin  admin address
     */
    function setAdmin(address _admin) external onlyOwner{
        require(_admin != address(0) && isContract(_admin) != true, "Admin can't be contract address & zero address");
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(4)));
        admin = _admin;    
    }

    /**
     * @dev Transfer AMINT token to the borrower
     * @param _borrower Address of the borrower to transfer
     * @param amount deposited amount of the borrower
     * @param _ethPrice current eth price
     */
    function _transferToken(address _borrower,uint256 amount,uint128 _ethPrice,uint256 optionFees) internal {
        require(_borrower != address(0), "Borrower cannot be zero address");
        require(LTV != 0, "LTV must be set to non-zero value before providing loans");
        
        // tokenValueConversion is in USD, and our stablecoin is pegged to USD in 1:1 ratio
        // Hence if tokenValueConversion = 1, then equivalent stablecoin tokens = tokenValueConversion

        uint256 tokensToLend = BorrowLib.tokensToLend(amount, _ethPrice, LTV);

        //Call the mint function in AMINT
        //Mint 80% - options fees to borrower
        bool minted = amint.mint(_borrower, (tokensToLend - optionFees));

        if(!minted){
            revert Borrowing_amintMintFailed();
        }

        //Mint options fees to treasury
        bool treasuryMint = amint.mint(treasuryAddress,optionFees);

        if(!treasuryMint){
            revert Borrowing_amintMintFailed();
        }
    }

    /**
     * @dev Transfer Abond token to the borrower
     * @param _toAddress Address of the borrower to transfer
     * @param _amount adond amount to transfer
     */

    function _mintAbondToken(address _toAddress, uint64 _index, uint256 _amount) internal returns(uint128){
        require(_toAddress != address(0), "Borrower cannot be zero address");
        require(_amount != 0,"Amount can't be zero");

        // ABOND:AMINT = 4:1
        uint128 amount = (uint128(_amount) * BorrowLib.AMINT_PRECISION)/bondRatio;

        //Call the mint function in ABONDToken
        bool minted = abond.mint(_toAddress, _index, amount);

        if(!minted){
            revert Borrowing_abondMintFailed();
        }
        return amount;
    }

    /**
    * @dev This function takes ethPrice, depositTime, percentageOfEth and receivedType parameters to deposit eth into the contract and mint them back the AMINT tokens.
    * @param _ethPrice get current eth price 
    * @param _depositTime get unixtime stamp at the time of deposit
    * @param _strikePercent percentage increase of eth price
    * @param _strikePrice strike price which the user opted
    * @param _volatility eth volatility
    **/

    function depositTokens (
        uint128 _ethPrice,
        uint64 _depositTime,
        IOptions.StrikePrice _strikePercent,
        uint64 _strikePrice,
        uint256 _volatility,
        uint256 _depositingAmount
    ) internal nonReentrant whenNotPaused(IMultiSign.Functions(0)) {
        require(msg.value > 0, "Cannot deposit zero tokens");
        require(msg.value > _depositingAmount,"Borrowing: Don't have enough LZ fee");

        bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        uint8[] memory structIndex;
        //! calculting fee 
        MessagingFee memory fee = quote(dstEid, omniChainBorrowing, structIndex, _options, false);
        MessagingFee memory cdsLzFee = cds.quote(dstEid, CDSInterface.FunctionToDo(1), 0, _options, false);

        //Call calculateInverseOfRatio function to find ratio
        uint64 ratio = calculateRatio(_depositingAmount,uint128(_ethPrice));
        require(ratio >= (2 * BorrowLib.RATIO_PRECISION),"Not enough fund in CDS");

        // Call calculateOptionPrice in options contract to get options fees
        uint256 optionFees = options.calculateOptionPrice(_ethPrice,_volatility,_depositingAmount,_strikePercent);
        uint256 tokensToLend = BorrowLib.tokensToLend(_depositingAmount, _ethPrice, LTV);
        uint256 borrowAmount = tokensToLend - optionFees;
        
        //Call the deposit function in Treasury contract
        ITreasury.DepositResult memory depositResult = treasury.deposit{value:(msg.value - fee.nativeFee - cdsLzFee.nativeFee)}(
                _depositingAmount,
                msg.sender,_ethPrice,_depositTime);
        uint64 index = depositResult.borrowerIndex;
        //Check whether the deposit is successfull
        if(!depositResult.hasDeposited){
            revert Borrowing_DepositFailed();
        }
        abond.setAbondData(msg.sender, index, (uint128(_depositingAmount) * 50)/100, treasury.getExternalProtocolCumulativeRate(true));
        // Call the transfer function to mint AMINT
        _transferToken(msg.sender,_depositingAmount,_ethPrice,optionFees);

        // Call calculateCumulativeRate in cds to split fees to cds users
        cds.calculateCumulativeRate{ value: cdsLzFee.nativeFee}(uint128(optionFees));

        //Get the deposit details from treasury
        ITreasury.GetBorrowingResult memory getBorrowingResult = treasury.getBorrowing(msg.sender,index);
        ITreasury.DepositDetails memory depositDetail = getBorrowingResult.depositDetails;
        depositDetail.borrowedAmount = uint128(borrowAmount);
        depositDetail.optionFees = uint128(optionFees);

        //Update variables in treasury
        treasury.updateHasBorrowed(msg.sender,true);
        treasury.updateTotalBorrowedAmount(msg.sender,borrowAmount);

        //Call calculateCumulativeRate() to get currentCumulativeRate
        uint256 currentCumulativeRate = calculateCumulativeRate();
        lastEventTime = uint128(block.timestamp);

        // Calculate normalizedAmount
        uint256 normalizedAmount = (borrowAmount * BorrowLib.RATE_PRECISION)/currentCumulativeRate;

        depositDetail.normalizedAmount = uint128(normalizedAmount);
        depositDetail.strikePrice = _strikePrice * uint128(_depositingAmount);

        //Update the deposit details
        treasury.updateDepositDetails(msg.sender,index,depositDetail);

        // Calculate normalizedAmount of Protocol
        totalNormalizedAmount += normalizedAmount;
        lastEthprice = uint128(_ethPrice);
        
        //! updating global data 
        omniChainBorrowing.normalizedAmount += normalizedAmount;  

        emit Deposit(index,_depositingAmount,borrowAmount,normalizedAmount);
    }

    /**
    @dev This function withdraw ETH.
    @param _toAddress The address to whom to transfer ETH.
    @param _index Index of the borrow
    @param _ethPrice Current ETH Price.
    @param _withdrawTime time right now
    **/

    function withDraw(
        address _toAddress,
        uint64 _index,
        uint64 _ethPrice,
        uint64 _withdrawTime
    ) internal nonReentrant whenNotPaused(IMultiSign.Functions(1)){
        // check is _toAddress in not a zero address and isContract address
        require(_toAddress != address(0) && isContract(_toAddress) != true, "To address cannot be a zero and contract address");
        
        calculateRatio(0,_ethPrice);
        lastEthprice = uint128(_ethPrice);

        ITreasury.GetBorrowingResult memory getBorrowingResult = treasury.getBorrowing(msg.sender,_index);
        ITreasury.DepositDetails memory depositDetail = getBorrowingResult.depositDetails;

        // check if borrowerIndex in BorrowerDetails of the msg.sender is greater than or equal to Index
        if(getBorrowingResult.totalIndex >= _index ) {
            // Check if user amount in the Index is been liquidated or not
            require(!depositDetail.liquidated,"User amount has been liquidated");
            // check if withdrawed in depositDetail in borrowing of msg.seader is false or not
            if(depositDetail.withdrawed == false) {                                  
                // Calculate the borrowingHealth
                uint128 borrowingHealth = (_ethPrice * 10000) / depositDetail.ethPriceAtDeposit;
                require(borrowingHealth > 8000,"BorrowingHealth is Low");
                // Calculate th borrower's debt
                uint256 borrowerDebt = ((depositDetail.normalizedAmount * lastCumulativeRate)/BorrowLib.RATE_PRECISION);
                calculateCumulativeRate();
                lastEventTime = uint128(block.timestamp);
                // Check whether the Borrower have enough Trinty
                require(amint.balanceOf(msg.sender) >= borrowerDebt, "User balance is less than required");
                            
                // Update the borrower's data
                {depositDetail.ethPriceAtWithdraw = _ethPrice;
                depositDetail.withdrawed = true;
                depositDetail.withdrawTime = _withdrawTime;
                // Calculate interest for the borrower's debt
                //uint256 interest = borrowerDebt - depositDetail.borrowedAmount;

                uint256 discountedETH = ((((80*((depositDetail.depositedAmount * 50)/100))/100)*_ethPrice)/100)/BorrowLib.AMINT_PRECISION; // 0.4
                treasury.updateAbondAmintPool(discountedETH,true);
                // Calculate the amount of AMINT to burn and sent to the treasury
                // uint256 halfValue = (50 *(depositDetail.borrowedAmount))/100;
                //!console.log("BORROWED AMOUNT",depositDetail.borrowedAmount);
                //!console.log("DISCOUNTED ETH",discountedETH);
                uint256 burnValue = depositDetail.borrowedAmount - discountedETH;
                //!console.log("BURN VALUE",burnValue);
                // Burn the AMINT from the Borrower
                bool success = amint.burnFromUser(msg.sender, burnValue);
                if(!success){
                    revert Borrowing_WithdrawBurnFailed();
                }

                //Transfer the remaining AMINT to the treasury
                bool transfer = amint.transferFrom(msg.sender,treasuryAddress,borrowerDebt - burnValue);
                if(!transfer){
                    revert Borrowing_WithdrawAMINTTransferFailed();
                }
                //Update totalNormalizedAmount
                totalNormalizedAmount -= depositDetail.normalizedAmount;
                omniChainBorrowing.normalizedAmount -= depositDetail.normalizedAmount;
                //!console.log("borrowerDebt",borrowerDebt);
                treasury.updateTotalInterest(borrowerDebt - depositDetail.borrowedAmount);

                // Mint the ABondTokens
                uint128 noOfAbondTokensminted = _mintAbondToken(msg.sender, _index, discountedETH);
                // Update ABONDToken data
                depositDetail.aBondTokensAmount = noOfAbondTokensminted;

                // Update deposit details    
                treasury.updateDepositDetails(msg.sender,_index,depositDetail);}             
                uint128 ethToReturn;
                //Calculate current depositedAmount value
                uint128 depositedAmountvalue = (depositDetail.depositedAmount * depositDetail.ethPriceAtDeposit)/_ethPrice;

                if(borrowingHealth > 10000){
                    // If the ethPrice is higher than deposit ethPrice,call withdrawOption in options contract
                    ethToReturn = (depositedAmountvalue + (options.calculateStrikePriceGains(depositDetail.depositedAmount,depositDetail.strikePrice,_ethPrice)));
                    if(ethToReturn > depositDetail.depositedAmount){
                        ethRemainingInWithdraw += (ethToReturn - depositDetail.depositedAmount);
                        omniChainBorrowing.ethRemainingInWithdraw += (ethToReturn - depositDetail.depositedAmount);
                    }else{
                        ethRemainingInWithdraw += (depositDetail.depositedAmount - ethToReturn);
                        omniChainBorrowing.ethRemainingInWithdraw += (depositDetail.depositedAmount - ethToReturn);
                    }
                    ethValueRemainingInWithdraw += (ethRemainingInWithdraw * _ethPrice);
                    omniChainBorrowing.ethValueRemainingInWithdraw += (ethRemainingInWithdraw * _ethPrice);
                }else if(borrowingHealth == 10000){
                    ethToReturn = depositedAmountvalue;
                }else if(8000 < borrowingHealth && borrowingHealth < 10000) {
                    ethToReturn = depositDetail.depositedAmount;
                }else{
                    revert("BorrowingHealth is Low");
                }
                ethToReturn = (ethToReturn * 50)/100;

                bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
                uint8[] memory structIndex;
                //! calculting fee 
                MessagingFee memory fee = quote(dstEid, omniChainBorrowing, structIndex, _options, false);

                // Call withdraw in treasury
                bool sent = treasury.withdraw{value:(msg.value - fee.nativeFee)}(msg.sender,_toAddress,ethToReturn,_index);
                if(!sent){
                    revert Borrowing_WithdrawEthTransferFailed();
                }
                emit Withdraw(borrowerDebt,ethToReturn,depositDetail.aBondTokensAmount);
            }else{
                // update withdrawed to true
                revert("User already withdraw entire amount");
            }
        }else {
            // revert if user doens't have the perticular index
            revert("User doens't have the perticular index");
        }
    }

    function redeemYields(address user,uint128 aBondAmount) public returns(uint256){
        return (BorrowLib.redeemYields(user, aBondAmount, address(amint), address(abond), address(treasury)));
    }

    function getAbondYields(address user,uint128 aBondAmount) public view returns(uint128,uint256,uint256){
        return (BorrowLib.getAbondYields(user, aBondAmount, address(abond), address(treasury)));
    }

    /**
     * @dev This function liquidate ETH which are below downside protection.
     * @param _user The address to whom to liquidate ETH.
     * @param _index Index of the borrow
     * @param currentEthPrice Current ETH Price.
     */

    function liquidate(
        address _user,
        uint64 _index,
        uint64 currentEthPrice
    ) internal whenNotPaused(IMultiSign.Functions(2)) onlyAdmin{

        // Check whether the liquidator 
        require(_user != address(0), "To address cannot be a zero address");
        require(msg.sender != _user,"You cannot liquidate your own assets!");
        address borrower = _user;
        uint64 index = _index;
        ++noOfLiquidations;
        ++omniChainBorrowing.noOfLiquidations;

        // Get the borrower details
        ITreasury.GetBorrowingResult memory getBorrowingResult = treasury.getBorrowing(borrower,index);
        ITreasury.DepositDetails memory depositDetail = getBorrowingResult.depositDetails;
        require(!depositDetail.liquidated,"Already Liquidated");
        
        // uint256 externalProtocolInterest = treasury.withdrawFromExternalProtocol(borrower,10000); // + treasury.withdrawFromCompoundByUser(borrower,index);

        require(
            depositDetail.depositedAmount <= (
                treasury.omniChainTreasuryTotalVolumeOfBorrowersAmountinWei() - treasury.omniChainTreasuryEthProfitsOfLiquidators())
            ,"Not enough funds in treasury");

        // Check whether the position is eligible or not for liquidation
        uint128 ratio = ((currentEthPrice * 10000) / depositDetail.ethPriceAtDeposit);
        require(ratio <= 8000,"You cannot liquidate");

        //Update the position to liquidated     
        depositDetail.liquidated = true;

        // Calculate borrower's debt 
        calculateCumulativeRate();
        uint256 borrowerDebt = ((depositDetail.normalizedAmount * lastCumulativeRate)/BorrowLib.RATE_PRECISION);
        uint128 returnToTreasury = uint128(borrowerDebt);
        // 20% to abond amint pool
        uint128 returnToAbond = (((((depositDetail.depositedAmount * depositDetail.ethPriceAtDeposit)/BorrowLib.AMINT_PRECISION)/100) - returnToTreasury) * 20)/100;
        treasury.updateAbondAmintPool(returnToAbond,true);
        // CDS profits
        uint128 cdsProfits = (((depositDetail.depositedAmount * depositDetail.ethPriceAtDeposit)/BorrowLib.AMINT_PRECISION)/100) - returnToTreasury - returnToAbond;
        uint128 liquidationAmountNeeded = returnToTreasury + returnToAbond;
        require(cds.omniChainCDSTotalAvailableLiquidationAmount() >= liquidationAmountNeeded,"Don't have enough AMINT in CDS to liquidate");
        
        CDSInterface.LiquidationInfo memory liquidationInfo;
        liquidationInfo = CDSInterface.LiquidationInfo(
            liquidationAmountNeeded,
            cdsProfits,
            depositDetail.depositedAmount,
            cds.omniChainCDSTotalAvailableLiquidationAmount());

        cds.updateLiquidationInfo(noOfLiquidations,liquidationInfo);
        cds.updateTotalCdsDepositedAmount(liquidationAmountNeeded - cdsProfits);
        cds.updateTotalCdsDepositedAmountWithOptionFees(liquidationAmountNeeded - cdsProfits);
        cds.updateTotalAvailableLiquidationAmount(liquidationAmountNeeded - cdsProfits);
        treasury.updateEthProfitsOfLiquidators(depositDetail.depositedAmount,true);
        //treasury.updateInterestFromExternalProtocol(externalProtocolInterest);

        //Update totalInterestFromLiquidation
        // uint256 totalInterestFromLiquidation = uint256(returnToTreasury - borrowerDebt + returnToAbond);
        // treasury.updateTotalInterestFromLiquidation(totalInterestFromLiquidation);
        treasury.updateDepositDetails(borrower,index,depositDetail);

        // Burn the borrow amount
        treasury.approveAmint(address(this),depositDetail.borrowedAmount);
        bool success = amint.burnFromUser(treasuryAddress, depositDetail.borrowedAmount);
        if(!success){
            revert Borrowing_LiquidateBurnFailed();
        }
        // Transfer ETH to CDS Pool
        emit Liquidate(index,liquidationAmountNeeded,cdsProfits,depositDetail.depositedAmount,cds.totalAvailableLiquidationAmount());
    }

    /**
     * @dev get the usd value of ETH
     */
    function getUSDValue() public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(price) / BorrowLib.PRECISION);
    }

    function setLTV(uint8 _LTV) external onlyAdmin {
        require(_LTV != 0, "LTV can't be zero");
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(0)));
        LTV = _LTV;
    }

    function setDstEid(uint32 _eid) external onlyAdmin{
        require(_eid != 0, "EID can't be zero");
        dstEid = _eid;
    }

    function setBondRatio(uint64 _bondRatio) external onlyAdmin {
        require(_bondRatio != 0, "Bond Ratio can't be zero");
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(8)));
        bondRatio = _bondRatio;
    }

    function getLTV() public view returns(uint8){
        return LTV;
    }

    function getLastEthVaultValue() public view returns(uint256){
        return (lastEthVaultValue/100);
    }

    function setWithdrawTimeLimit(uint64 _timeLimit) external onlyAdmin {
        require(_timeLimit != 0, "Withdraw time limit can't be zero");
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(2)));
        withdrawTimeLimit = _timeLimit;
    }

    /**
     * @dev update the last eth vault value
     * @param _amount eth vault value
     */
    function updateLastEthVaultValue(uint256 _amount) external onlyTreasury{
        require(_amount != 0,"Last ETH vault value can't be zero");
        omniChainBorrowing.ethVaultValue -= _amount;
    }

    /**
     * @dev calculate the ratio of CDS Pool/Eth Vault
     * @param _amount amount to be depositing
     * @param currentEthPrice current eth price in usd
     */
    function calculateRatio(uint256 _amount,uint currentEthPrice) public returns(uint64){

        if(currentEthPrice == 0){
            revert Borrowing_GettingETHPriceFailed();
        }

        // Get the number of Borrowers
        uint128 noOfBorrowers = treasury.omniChainTreasuryNoOfBorrowers();

        uint256 latestTotalCDSPool = cds.omniChainCDSTotalCdsDepositedAmount();

        (uint64 ratio, OmniChainBorrowingData memory omniChainBorrowingFromLib) = BorrowLib.calculateRatio(
            _amount,
            currentEthPrice,
            lastEthprice,
            noOfBorrowers,
            latestTotalCDSPool,
            omniChainBorrowing  //! using global data instead of individual chain data
            );

        //! updating global data 
        omniChainBorrowing = omniChainBorrowingFromLib;

        // uint256 netPLCdsPool;

        // if(currentEthPrice == 0){
        //     revert BorrowLib.Borrowing_GettingETHPriceFailed();
        // }

        // // Get the number of Borrowers
        // uint128 noOfBorrowers = treasury.noOfBorrowers();

        // // Calculate net P/L of CDS Pool
        // if(currentEthPrice > lastEthprice){
        //     netPLCdsPool = (currentEthPrice - lastEthprice) * noOfBorrowers;
        // }else{
        //     netPLCdsPool = (lastEthprice - currentEthPrice) * noOfBorrowers;
        // }

        // uint256 currentEthVaultValue;
        // uint256 currentCDSPoolValue;
        // BorrowLib.OmniChainBorrowingData memory previousData = omniChainBorrowing;
 
        // // Check it is the first deposit
        // if(noOfBorrowers == 0){

        //     // Calculate the ethVault value
        //     // lastEthVaultValue = _amount * currentEthPrice;
        //     omniChainBorrowing.ethVaultValue = _amount * currentEthPrice;
        //     // Set the currentEthVaultValue to lastEthVaultValue for next deposit
        //     currentEthVaultValue = omniChainBorrowing.ethVaultValue;

        //     // Get the total amount in CDS
        //     // lastTotalCDSPool = cds.totalCdsDepositedAmount();
        //     omniChainBorrowing.totalCDSPool = cds.totalCdsDepositedAmount();

        //     if (currentEthPrice >= lastEthprice){
        //         currentCDSPoolValue = omniChainBorrowing.totalCDSPool + netPLCdsPool;
        //     }else{
        //         currentCDSPoolValue = omniChainBorrowing.totalCDSPool - netPLCdsPool;
        //     }

        //     // Set the currentCDSPoolValue to lastCDSPoolValue for next deposit
        //     currentCDSPoolValue = currentCDSPoolValue * BorrowLib.AMINT_PRECISION;
        //     omniChainBorrowing.cdsPoolValue = currentCDSPoolValue;

        // }else{

        //     currentEthVaultValue = previousData.ethVaultValue + (_amount * currentEthPrice);
        //     omniChainBorrowing.ethVaultValue = currentEthVaultValue;

        //     uint256 latestTotalCDSPool = cds.totalCdsDepositedAmount();

        //     if(currentEthPrice >= lastEthprice){
        //         if(latestTotalCDSPool > previousData.totalCDSPool){
        //             omniChainBorrowing.cdsPoolValue = previousData.cdsPoolValue + (
        //                 latestTotalCDSPool - previousData.totalCDSPool) + netPLCdsPool;  
        //         }else{
        //             omniChainBorrowing.cdsPoolValue = previousData.cdsPoolValue - (
        //                 previousData.totalCDSPool - latestTotalCDSPool) + netPLCdsPool;
        //         }
        //     }else{
        //         if(latestTotalCDSPool > previousData.totalCDSPool){
        //             omniChainBorrowing.cdsPoolValue = previousData.cdsPoolValue + (
        //                 latestTotalCDSPool - previousData.totalCDSPool) - netPLCdsPool;  
        //         }else{
        //             omniChainBorrowing.cdsPoolValue = previousData.cdsPoolValue - (
        //                 previousData.totalCDSPool - latestTotalCDSPool) - netPLCdsPool;
        //         }
        //     }

        //     omniChainBorrowing.totalCDSPool = latestTotalCDSPool;
        //     currentCDSPoolValue = omniChainBorrowing.cdsPoolValue * BorrowLib.AMINT_PRECISION;
        // }

        // // Calculate ratio by dividing currentEthVaultValue by currentCDSPoolValue,
        // // since it may return in decimals we multiply it by 1e6
        // uint64 ratio = uint64((currentCDSPoolValue * BorrowLib.CUMULATIVE_PRECISION)/currentEthVaultValue);
        return ratio;
    }

    function setAPR(uint128 _ratePerSec) external whenNotPaused(IMultiSign.Functions(3)) onlyAdmin{
        require(_ratePerSec != 0,"Rate should not be zero");
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(1)));
        ratePerSec = _ratePerSec;
    }

    /**
     * @dev calculate cumulative rate 
     */
    function calculateCumulativeRate() public returns(uint256){
        // Get the noOfBorrowers
        uint128 noOfBorrowers = treasury.noOfBorrowers();

        uint256 currentCumulativeRate = BorrowLib.calculateCumulativeRate(noOfBorrowers, ratePerSec, lastEventTime, lastCumulativeRate);
        lastCumulativeRate = currentCumulativeRate;
        return currentCumulativeRate;
    }

    function omniChainBorrowingCDSPoolValue() external view returns(uint256){
        return omniChainBorrowing.cdsPoolValue;
    }

    function getOmniChainBorrowing() external view returns(OmniChainBorrowingData memory){
        return omniChainBorrowing;
    }

    /**
     * @dev only user interaction function
     */

    function send( BorrowFunction _borrowFunction, bytes calldata _data )
        external payable returns (MessagingReceipt memory receipt) {

        (        
            uint64 _ethPrice,
            uint64 _time,
            uint256 _depositingAmount,
            IOptions.StrikePrice _strikePercent,
            uint64 _strikePrice,
            uint256 _volatility,
            address _user,
            uint64 _index
        ) = abi.decode(_data, (
            uint64,
            uint64,
            uint256,
            IOptions.StrikePrice,
            uint64,
            uint256,
            address,
            uint64));

        if(_borrowFunction == BorrowFunction.DEPOSIT){

            depositTokens( _ethPrice, _time, _strikePercent, _strikePrice, _volatility, _depositingAmount);

        }else if(_borrowFunction == BorrowFunction.WITHDRAW){

            withDraw( _user, _index, _ethPrice, _time);

        }else if(_borrowFunction == BorrowFunction.LIQUIDATION){
            liquidate( _user, _index, _ethPrice);
        }

        //! getting options since,the src don't know the dst state
        bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        uint8[] memory structIndex;

        //! calculting fee 
        MessagingFee memory fee = quote(dstEid, omniChainBorrowing, structIndex, _options, false);

        //! encoding the message 
        bytes memory _payload = abi.encode( omniChainBorrowing, structIndex);

        //! Calling layer zero send function to send to dst chain
        receipt = _lzSend(dstEid, _payload, _options, fee, payable(msg.sender));
    }

    function quote(
        uint32 _dstEid,
        OmniChainBorrowingData memory _message,
        uint8[] memory indices,
        bytes memory _options,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(_message,indices);
        fee = _quote(_dstEid, payload, _options, _payInLzToken);
    }

    /**
     * @dev function to receive data from src
     */
    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override{

        uint8[] memory index;

        OmniChainBorrowingData memory data;

        //! Decoding the message from src
        (data,index) = abi.decode(payload, (OmniChainBorrowingData, uint8[]));


        if(index.length > 0){
            // bytes memory _payload = abi.encode();
            // bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(50000, 0);
            // MessagingFee memory fee = quote(dstEid, ,[], _options, false);
            // _lzSend(dstEid, _payload, _options, fee, payable(msg.sender));
        }else{

            omniChainBorrowing = data;
        }
    }
    receive() external payable{}
}