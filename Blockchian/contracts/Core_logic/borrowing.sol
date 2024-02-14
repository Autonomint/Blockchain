// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interface/CDSInterface.sol";
import "../interface/IAmint.sol";
import "../interface/IAbond.sol";
import "../interface/ITreasury.sol";
import "../interface/IOptions.sol";
import "../interface/IMultiSign.sol";
import "hardhat/console.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract Borrowing is Initializable,OwnableUpgradeable,UUPSUpgradeable,ReentrancyGuardUpgradeable {

    error Borrowing_DepositFailed();
    error Borrowing_GettingETHPriceFailed();
    error Borrowing_amintMintFailed();
    error Borrowing_abondMintFailed();
    error Borrowing_WithdrawAMINTTransferFailed();
    error Borrowing_WithdrawEthTransferFailed();
    error Borrowing_WithdrawBurnFailed();
    error Borrowing_LiquidateBurnFailed();
    error Borrowing_LiquidateEthTransferToCdsFailed();

    IAMINT public amint; // our stablecoin

    CDSInterface public cds;

    IABONDToken public abond; // abond stablecoin

    ITreasury public treasury;

    IOptions public options; // options contract interface

    IMultiSign public multiSign;

    uint256 private _downSideProtectionLimit;
    
    enum DownsideProtectionLimitValue {
        // 0: deside Downside Protection limit by percentage of eth price in past 3 months
        ETH_PRICE_VOLUME,
        // 1: deside Downside Protection limit by CDS volume divided by borrower volume.
        CDS_VOLUME_BY_BORROWER_VOLUME
    }

    address public treasuryAddress; // treasury contract address
    address public cdsAddress; // CDS contract address
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

    uint128 private PRECISION; // ETH price precision
    uint128 private CUMULATIVE_PRECISION;
    uint128 private RATIO_PRECISION;
    uint128 private RATE_PRECISION;
    uint128 private AMINT_PRECISION;

    event Deposit(uint64 index,uint256 depositedAmount,uint256 borrowAmount,uint256 normalizedAmount);
    event Withdraw(uint256 borrowDebt,uint128 withdrawAmount,uint128 noOfAbond);
    event Liquidate(uint64 index,uint128 liquidationAmount,uint128 profits,uint128 ethAmount,uint256 availableLiquidationAmount);

    function initialize( 
        address _tokenAddress,
        address _cds,
        address _abondToken,
        address _multiSign,
        address _priceFeedAddress,
        uint64 chainId
        ) initializer public{
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        amint = IAMINT(_tokenAddress);
        cds = CDSInterface(_cds);
        cdsAddress = _cds;
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
        PRECISION = 1e6;
        CUMULATIVE_PRECISION = 1e7;
        RATIO_PRECISION = 1e4;
        RATE_PRECISION = 1e27;
        AMINT_PRECISION = 1e12;
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
        
        uint256 tokenValueConversion = (amount * _ethPrice)/AMINT_PRECISION; // dummy data

        // tokenValueConversion is in USD, and our stablecoin is pegged to USD in 1:1 ratio
        // Hence if tokenValueConversion = 1, then equivalent stablecoin tokens = tokenValueConversion

        uint256 tokensToLend = (tokenValueConversion * LTV) / RATIO_PRECISION;

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

    function _mintAbondToken(address _toAddress,uint256 _amount) internal returns(uint128){
        require(_toAddress != address(0), "Borrower cannot be zero address");
        require(_amount != 0,"Amount can't be zero");

        // ABOND:AMINT = 4:1
        uint128 amount = (uint128(_amount) * 100)/(bondRatio * 100);

        //Call the mint function in ABONDToken
        bool minted = abond.mint(_toAddress,amount);

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
        uint256 _volatility
    ) external payable nonReentrant whenNotPaused(IMultiSign.Functions(0)){
        require(msg.value > 0, "Cannot deposit zero tokens");
        require(msg.sender.balance > msg.value, "You do not have sufficient balance to execute this transaction");

        //Call calculateInverseOfRatio function to find ratio
        uint64 ratio = calculateRatio(msg.value,uint128(_ethPrice));
        require(ratio >= (2 * RATIO_PRECISION),"Not enough fund in CDS");

        // Call calculateOptionPrice in options contract to get options fees
        uint256 optionFees = options.calculateOptionPrice(_ethPrice,_volatility,msg.value,_strikePercent);

        uint256 tokensToLend = (msg.value * _ethPrice * LTV) / (AMINT_PRECISION * RATIO_PRECISION);
        uint256 borrowAmount = tokensToLend - optionFees;
        
        //Call the deposit function in Treasury contract
        ITreasury.DepositResult memory depositResult = treasury.deposit{value:msg.value}(msg.sender,_ethPrice,_depositTime);
        uint64 index = depositResult.borrowerIndex;
        //Check whether the deposit is successfull
        if(!depositResult.hasDeposited){
            revert Borrowing_DepositFailed();
        }

        // Call the transfer function to mint AMINT
        _transferToken(msg.sender,msg.value,_ethPrice,optionFees);

        // Call calculateCumulativeRate in cds to split fees to cds users
        cds.calculateCumulativeRate(uint128(optionFees));

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
        uint256 normalizedAmount = (borrowAmount * RATE_PRECISION * RATE_PRECISION)/currentCumulativeRate;

        depositDetail.normalizedAmount = uint128(normalizedAmount);
        depositDetail.strikePrice = _strikePrice * uint128(msg.value);

        //Update the deposit details
        treasury.updateDepositDetails(msg.sender,index,depositDetail);

        // Calculate normalizedAmount of Protocol
        totalNormalizedAmount += normalizedAmount;
        lastEthprice = uint128(_ethPrice);
        emit Deposit(index,msg.value,borrowAmount,normalizedAmount);
    }

    /**
     * @dev deposit the eth in our protocol to Aave
     */
    // function depositToAaveProtocol() external onlyOwner{
    //     treasury.depositToAave();
    // }

    /**
     * @dev withdraw the eth from aave which were already deposited
     */
    // function withdrawFromAaveProtocol(uint64 index) external onlyOwner{
    //     treasury.withdrawFromAave(index);
    // }

    /**
     * @dev deposit the eth in our protocol to Compound
     */
    // function depositToCompoundProtocol() external onlyOwner{
    //     treasury.depositToCompound();
    // }

    /**
     * @dev withdraw the eth from Compound which were already deposited
     * @param index index of the deposit
     */
    // function withdrawFromCompoundProtocol(uint64 index) external onlyOwner{
    //     treasury.withdrawFromCompound(index);
    // }

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
    ) external nonReentrant whenNotPaused(IMultiSign.Functions(1)){
        // check is _toAddress in not a zero address and isContract address
        require(_toAddress != address(0) && isContract(_toAddress) != true, "To address cannot be a zero and contract address");

        lastEthprice = uint128(_ethPrice);

        ITreasury.GetBorrowingResult memory getBorrowingResult = treasury.getBorrowing(msg.sender,_index);
        ITreasury.DepositDetails memory depositDetail = getBorrowingResult.depositDetails;

        // check if borrowerIndex in BorrowerDetails of the msg.sender is greater than or equal to Index
        if(getBorrowingResult.totalIndex >= _index ) {
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
                    lastEventTime = uint128(block.timestamp);
                    // Check whether the Borrower have enough Trinty
                    require(amint.balanceOf(msg.sender) >= borrowerDebt, "User balance is less than required");
                            
                    // Update the borrower's data
                    {depositDetail.ethPriceAtWithdraw = _ethPrice;
                    depositDetail.withdrawTime = _withdrawTime;
                    depositDetail.withdrawNo = 1;
                    // Calculate interest for the borrower's debt
                    //uint256 interest = borrowerDebt - depositDetail.borrowedAmount;

                    uint256 discountedETH = ((((80*((depositDetail.depositedAmount * 50)/100))/100)*_ethPrice)/100)/AMINT_PRECISION; // 0.4
                    treasury.updateAbondAmintPool(discountedETH,true);
                    // Calculate the amount of AMINT to burn and sent to the treasury
                    // uint256 halfValue = (50 *(depositDetail.borrowedAmount))/100;
                    uint256 burnValue = depositDetail.borrowedAmount - discountedETH;

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

                    treasury.updateTotalInterest(borrowerDebt - depositDetail.borrowedAmount);

                    // Mint the ABondTokens
                    uint128 noOfAbondTokensminted = _mintAbondToken(msg.sender,discountedETH);

                    // Update ABONDToken data
                    depositDetail.burnedAmint = burnValue;
                    depositDetail.aBondTokensAmount = noOfAbondTokensminted;
                    treasury.updateTotalAbondTokensIncrease(msg.sender,noOfAbondTokensminted);
                    // Update deposit details    
                    treasury.updateDepositDetails(msg.sender,_index,depositDetail);}             
                    uint128 ethToReturn;
                    //Calculate current depositedAmount value
                    uint128 depositedAmountvalue = (depositDetail.depositedAmount * depositDetail.ethPriceAtDeposit)/_ethPrice;

                    if(borrowingHealth > 10000){
                        // If the ethPrice is higher than deposit ethPrice,call withdrawOption in options contract
                        ethToReturn = (depositedAmountvalue + (options.withdrawOption(depositDetail.depositedAmount,depositDetail.strikePrice,_ethPrice)));
                    }else if(borrowingHealth == 10000){
                        ethToReturn = depositedAmountvalue;
                    }else if(8000 < borrowingHealth && borrowingHealth < 10000) {
                        ethToReturn = depositDetail.depositedAmount;
                    }else{
                        revert("BorrowingHealth is Low");
                    }
                    ethToReturn = (ethToReturn * 50)/100;
                    // Call withdraw in treasury
                bool sent = treasury.withdraw(msg.sender,_toAddress,ethToReturn,_index);
                if(!sent){
                    revert Borrowing_WithdrawEthTransferFailed();
                }
                emit Withdraw(borrowerDebt,ethToReturn,depositDetail.aBondTokensAmount);
                }// Check whether it is second withdraw
                else if(depositDetail.withdrawNo == 1){
                    secondWithdraw(
                        _toAddress,
                        _index,
                        depositDetail.withdrawTime,
                        depositDetail.aBondTokensAmount,
                        depositDetail.withdrawAmount);
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
     * @param aBondTokensAmount Amount of pTokens transferred.
     * @param withdrawTime time at first withdraw
     * @param ethToReturn ethToReturn
     */

    function secondWithdraw(
        address _toAddress,
        uint64 _index,
        uint64 withdrawTime,
        uint128 aBondTokensAmount,
        uint128 ethToReturn
    ) internal {
            // Check whether the first withdraw passed one month
            require(block.timestamp >= (withdrawTime + withdrawTimeLimit),"Can't withdraw before the withdraw time limit");

            // Check the user has required pToken
            require(abond.balanceOf(msg.sender) == aBondTokensAmount,"Don't have enough ABOND Tokens");
            ITreasury.GetBorrowingResult memory getBorrowingResult = treasury.getBorrowing(msg.sender,_index);
            ITreasury.DepositDetails memory depositDetail = getBorrowingResult.depositDetails;
            // Update Borrower's Data
            treasury.updateTotalDepositedAmount(msg.sender,uint128(depositDetail.depositedAmount));
            depositDetail.withdrawed = true;
            depositDetail.withdrawNo = 2;
            treasury.updateTotalAbondTokensDecrease(msg.sender,aBondTokensAmount);
            depositDetail.aBondTokensAmount = 0;
            treasury.updateDepositDetails(msg.sender,_index,depositDetail);
            uint256 discountedETH = depositDetail.borrowedAmount - depositDetail.burnedAmint;
            treasury.updateAbondAmintPool(discountedETH,false);

            //Burn the amint from treasury
            treasury.approveAmint(address(this),discountedETH);
            bool transfer = amint.burnFromUser(treasuryAddress,discountedETH);
            if(!transfer){
                revert Borrowing_WithdrawBurnFailed();
            }
            //Burn the abond from user
            bool success = abond.burnFromUser(msg.sender,aBondTokensAmount);
            if(!success){
                revert Borrowing_WithdrawBurnFailed();
            }
            // Call withdraw function in Treasury
            bool sent = treasury.withdraw(msg.sender,_toAddress,ethToReturn,_index);
            if(!sent){
                revert Borrowing_WithdrawEthTransferFailed();
            }
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
    ) external whenNotPaused(IMultiSign.Functions(2)) onlyAdmin{

        // Check whether the liquidator 
        require(_user != address(0), "To address cannot be a zero address");
        require(msg.sender != _user,"You cannot liquidate your own assets!");
        address borrower = _user;
        uint64 index = _index;
        ++noOfLiquidations;

        // Get the borrower details
        ITreasury.GetBorrowingResult memory getBorrowingResult = treasury.getBorrowing(borrower,index);
        ITreasury.DepositDetails memory depositDetail = getBorrowingResult.depositDetails;
        require(!depositDetail.liquidated,"Already Liquidated");
        
        uint256 externalProtocolInterest = treasury.withdrawFromAaveByUser(borrower,index) + treasury.withdrawFromCompoundByUser(borrower,index);

        require(
            depositDetail.depositedAmount <= (treasury.totalVolumeOfBorrowersAmountinWei() - treasury.ethProfitsOfLiquidators())
            ,"Not enough funds in treasury");

        // Check whether the position is eligible or not for liquidation
        uint128 ratio = ((currentEthPrice * 10000) / depositDetail.ethPriceAtDeposit);
        require(ratio <= 8000,"You cannot liquidate");

        //Update the position to liquidated     
        depositDetail.liquidated = true;

        // Calculate borrower's debt 
        uint256 borrowerDebt = ((depositDetail.normalizedAmount * lastCumulativeRate)/RATE_PRECISION);
        lastCumulativeRate = calculateCumulativeRate()/RATE_PRECISION;
        uint128 returnToTreasury = uint128(borrowerDebt);
        // 20% to abond amint pool
        uint128 returnToAbond = (((((depositDetail.depositedAmount * depositDetail.ethPriceAtDeposit)/AMINT_PRECISION)/100) - returnToTreasury) * 20)/100;
        // CDS profits
        uint128 cdsProfits = (((depositDetail.depositedAmount * depositDetail.ethPriceAtDeposit)/AMINT_PRECISION)/100) - returnToTreasury - returnToAbond;
        uint128 liquidationAmountNeeded = returnToTreasury + returnToAbond;
        
        CDSInterface.LiquidationInfo memory liquidationInfo;
        liquidationInfo = CDSInterface.LiquidationInfo(liquidationAmountNeeded,cdsProfits,depositDetail.depositedAmount,cds.totalAvailableLiquidationAmount());

        cds.updateLiquidationInfo(noOfLiquidations,liquidationInfo);
        cds.updateTotalCdsDepositedAmount(liquidationAmountNeeded);
        cds.updateTotalCdsDepositedAmountWithOptionFees(liquidationAmountNeeded);
        cds.updateTotalAvailableLiquidationAmount(liquidationAmountNeeded);
        treasury.updateEthProfitsOfLiquidators(depositDetail.depositedAmount,true);
        treasury.updateInterestFromExternalProtocol(externalProtocolInterest);

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
        return (uint256(price) / PRECISION);
    }

    function setLTV(uint8 _LTV) external onlyAdmin {
        require(_LTV != 0, "LTV can't be zero");
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(0)));
        LTV = _LTV;
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
        lastEthVaultValue -= _amount;
    }

    /**
     * @dev calculate the ratio of CDS Pool/Eth Vault
     * @param _amount amount to be depositing
     * @param currentEthPrice current eth price in usd
     */
    function calculateRatio(uint256 _amount,uint currentEthPrice) public returns(uint64){

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
            currentCDSPoolValue = lastCDSPoolValue * AMINT_PRECISION;
        }else{

            currentEthVaultValue = lastEthVaultValue + (_amount * currentEthPrice);
            lastEthVaultValue = currentEthVaultValue;

            uint256 latestTotalCDSPool = cds.totalCdsDepositedAmount();

            if(currentEthPrice >= lastEthprice){
                if(latestTotalCDSPool > lastTotalCDSPool){
                    lastCDSPoolValue = lastCDSPoolValue + (latestTotalCDSPool - lastTotalCDSPool) + netPLCdsPool;  
                }else{
                    lastCDSPoolValue = lastCDSPoolValue - (lastTotalCDSPool - latestTotalCDSPool) + netPLCdsPool;
                }
            }else{
                if(latestTotalCDSPool > lastTotalCDSPool){
                    lastCDSPoolValue = lastCDSPoolValue + (latestTotalCDSPool - lastTotalCDSPool) - netPLCdsPool;  
                }else{
                    lastCDSPoolValue = lastCDSPoolValue - (lastTotalCDSPool - latestTotalCDSPool) - netPLCdsPool;
                }
            }

            lastTotalCDSPool = latestTotalCDSPool;
            currentCDSPoolValue = lastCDSPoolValue * AMINT_PRECISION;
        }

        // Calculate ratio by dividing currentEthVaultValue by currentCDSPoolValue,
        // since it may return in decimals we multiply it by 1e6
        uint64 ratio = uint64((currentCDSPoolValue * CUMULATIVE_PRECISION)/currentEthVaultValue);
        return ratio;
    }

    function setAPR(uint128 _ratePerSec) external whenNotPaused(IMultiSign.Functions(3)) onlyAdmin{
        require(_ratePerSec != 0,"Rate should not be zero");
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(1)));
        ratePerSec = _ratePerSec;
    }

    // function getAPY() public view returns(uint8){
    //     return APY;
    // }

    /**
     * @dev calculate cumulative rate 
     */
    function calculateCumulativeRate() public returns(uint256){
        // Get the noOfBorrowers
        uint128 noOfBorrowers = treasury.noOfBorrowers();

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

    // function permit(address holder, address spender, uint256 allowedAmount, bool allowed, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external view returns(bool){

    //     require(expiry == 0 || block.timestamp <= expiry, "Permit/expired");

    //     bytes32 permitHash =
    //         keccak256(abi.encodePacked(
    //             "\x19\x01",
    //             DOMAIN_SEPARATOR,
    //             keccak256(abi.encode(PERMIT_TYPEHASH,
    //                                  holder,
    //                                  spender,
    //                                  allowedAmount,
    //                                  allowed,
    //                                  expiry
    //                                  ))
    //     ));

    //     require(holder != address(0), "Permit/Invalid address");
    //     require(holder == ecrecover(permitHash, v, r, s), "Permit/invalid-permit");

    //     return true;
    // }

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