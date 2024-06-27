// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interface/CDSInterface.sol";
import "../interface/IBorrowing.sol";
import "../interface/IUSDa.sol";
import "../interface/IBorrowLiquidation.sol";
import { IABONDToken } from "../interface/IAbond.sol";
import { BorrowLib } from "../lib/BorrowLib.sol";
import "../interface/ITreasury.sol";
import "../interface/IOptions.sol";
import "../interface/IMultiSign.sol";
import "../interface/IGlobalVariables.sol";
import "hardhat/console.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

contract Borrowing is IBorrowing,Initializable,UUPSUpgradeable,ReentrancyGuardUpgradeable,OwnableUpgradeable{

    IUSDa  public usda; // our stablecoin
    CDSInterface    private cds;
    IABONDToken private abond; // abond stablecoin
    ITreasury   private treasury;
    IOptions    private options; // options contract interface
    IMultiSign  private multiSign;
    IBorrowLiquidation private borrowLiquiation;

    uint256 private _downSideProtectionLimit;
    address private treasuryAddress; // treasury contract address
    address public admin; // admin address
    uint8   private LTV; // LTV is a percentage eg LTV = 60 is 60%, must be divided by 100 in calculations
    uint8   private APR; 
    uint256 private totalNormalizedAmount; // total normalized amount in protocol
    address private priceFeedAddress; // ETH USD pricefeed address
    uint128 private lastEthprice; // previous eth price
    uint256 private lastEthVaultValue; // previous eth vault value
    uint256 private lastCDSPoolValue; // previous CDS pool value
    uint256 private lastTotalCDSPool;
    uint256 public  lastCumulativeRate; // previous cumulative rate
    uint128 private lastEventTime;
    uint128 private noOfLiquidations; // total number of liquidation happened till now
    uint128 private ratePerSec;
    uint64  private bondRatio;
    bytes32 private DOMAIN_SEPARATOR;
    uint256 private ethRemainingInWithdraw;
    uint256 private ethValueRemainingInWithdraw;
    // uint32  private dstEid; //! dst id
    using OptionsBuilder for bytes;
    // OmniChainBorrowingData private omniChainBorrowing; //! omniChainBorrowing contains global borrowing data(all chains)
    IGlobalVariables private globalVariables;

    function initialize( 
        address _tokenAddress,
        address _cds,
        address _abondToken,
        address _multiSign,
        address _priceFeedAddress,
        uint64 chainId,
        address _globalVariables
    ) initializer public{
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        usda = IUSDa(_tokenAddress);
        cds = CDSInterface(_cds);
        abond = IABONDToken(_abondToken);
        multiSign = IMultiSign(_multiSign);
        globalVariables = IGlobalVariables(_globalVariables);
        priceFeedAddress = _priceFeedAddress;                       //0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint64 chainId,address verifyingContract)"),
            keccak256(bytes(BorrowLib.name)),
            keccak256(bytes(BorrowLib.version)),
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
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(5)));
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

    function setBorrowLiquidation(address _borrowLiquidation) external onlyAdmin{
        require(_borrowLiquidation != address(0) && isContract(_borrowLiquidation) != false, "Borrow Liquidation must be contract address & can't be zero address");
        borrowLiquiation = IBorrowLiquidation(_borrowLiquidation);
    }

    /**
     * @dev set admin address
     * @param _admin  admin address
     */
    function setAdmin(address _admin) external onlyOwner{
        require(_admin != address(0) && isContract(_admin) != true, "Admin can't be contract address & zero address");
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(3)));
        admin = _admin;    
    }

    /**
     * @dev Transfer USDa token to the borrower
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

        //Call the mint function in USDa
        //Mint 80% - options fees to borrower
        bool minted = usda.mint(_borrower, (tokensToLend - optionFees));

        if(!minted){
            revert Borrowing_usdaMintFailed();
        }

        //Mint options fees to treasury
        bool treasuryMint = usda.mint(treasuryAddress,optionFees);

        if(!treasuryMint){
            revert Borrowing_usdaMintFailed();
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

        // ABOND:USDa = 4:1
        uint128 amount = BorrowLib.abondToMint(_amount,bondRatio);

        //Call the mint function in ABONDToken
        bool minted = abond.mint(_toAddress, _index, amount);

        if(!minted){
            revert Borrowing_abondMintFailed();
        }
        return amount;
    }

    /**
    * @dev This function takes ethPrice, depositTime, percentageOfEth and receivedType parameters to deposit eth into the contract and mint them back the AMINT tokens.
    * @param _strikePercent percentage increase of eth price
    * @param _strikePrice strike price which the user opted
    * @param _volatility eth volatility
    **/

    function depositTokens (
        IOptions.StrikePrice _strikePercent,
        uint64 _strikePrice,
        uint256 _volatility,
        uint256 _depositingAmount
    ) external payable nonReentrant whenNotPaused(IMultiSign.Functions(0)) {
        require(_depositingAmount > 0, "Cannot deposit zero tokens");
        require(msg.value > _depositingAmount,"Borrowing: Don't have enough LZ fee");
        uint128 _ethPrice = uint128(getUSDValue());
        bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250000, 0);
        //! calculting fee 
        MessagingFee memory fee = globalVariables.quote(IGlobalVariables.FunctionToDo(1), _options, false);

        //Call calculateInverseOfRatio function to find ratio
        uint64 ratio = calculateRatio(_depositingAmount,uint128(_ethPrice));
        require(ratio >= (2 * BorrowLib.RATIO_PRECISION),"Not enough fund in CDS");

        // Call calculateOptionPrice in options contract to get options fees
        uint256 optionFees = options.calculateOptionPrice(_ethPrice,_volatility,_depositingAmount,_strikePercent);
        uint256 tokensToLend = BorrowLib.tokensToLend(_depositingAmount, _ethPrice, LTV);
        
        //Call the deposit function in Treasury contract
        ITreasury.DepositResult memory depositResult = treasury.deposit{value: _depositingAmount}(
                msg.sender,_ethPrice,uint64(block.timestamp));
        uint64 index = depositResult.borrowerIndex;
        //Check whether the deposit is successfull
        if(!depositResult.hasDeposited){
            revert Borrowing_DepositFailed();
        }
        abond.setAbondData(msg.sender, index, BorrowLib.calculateHalfValue(_depositingAmount), treasury.getExternalProtocolCumulativeRate(true));
        // Call the transfer function to mint USDa
        _transferToken(msg.sender,_depositingAmount,_ethPrice,optionFees);

        // Call calculateCumulativeRate in cds to split fees to cds users
        cds.calculateCumulativeRate(uint128(optionFees));

        //Get the deposit details from treasury
        ITreasury.GetBorrowingResult memory getBorrowingResult = treasury.getBorrowing(msg.sender,index);
        ITreasury.DepositDetails memory depositDetail = getBorrowingResult.depositDetails;
        depositDetail.borrowedAmount = uint128(tokensToLend);
        depositDetail.optionFees = uint128(optionFees);

        //Update variables in treasury
        treasury.updateHasBorrowed(msg.sender,true);
        treasury.updateTotalBorrowedAmount(msg.sender,tokensToLend);

        //Call calculateCumulativeRate() to get currentCumulativeRate
        calculateCumulativeRate();
        lastEventTime = uint128(block.timestamp);

        // Calculate normalizedAmount
        uint256 normalizedAmount = BorrowLib.calculateNormAmount(tokensToLend,lastCumulativeRate);

        depositDetail.normalizedAmount = uint128(normalizedAmount);
        depositDetail.strikePrice = _strikePrice * uint128(_depositingAmount);

        //Update the deposit details
        treasury.updateDepositDetails(msg.sender,index,depositDetail);

        // Calculate normalizedAmount of Protocol
        totalNormalizedAmount += normalizedAmount;
        lastEthprice = uint128(_ethPrice);
        
        //! updating global data 
        IGlobalVariables.OmniChainData memory omniChainData = globalVariables.getOmniChainData();
        omniChainData.normalizedAmount += normalizedAmount;
        ++omniChainData.noOfBorrowers;
        omniChainData.totalVolumeOfBorrowersAmountinWei += _depositingAmount;
        omniChainData.totalVolumeOfBorrowersAmountinUSD += (_ethPrice * _depositingAmount);

        globalVariables.setOmniChainData(omniChainData);
        //! Calling Omnichain send function
        globalVariables.send{value:fee.nativeFee}(IGlobalVariables.FunctionToDo(1), fee, _options,msg.sender);

        emit Deposit(msg.sender,index,_depositingAmount,normalizedAmount,block.timestamp,_ethPrice,tokensToLend,_strikePrice,optionFees,_strikePercent,APR);
    }

    /**
    @dev This function withdraw ETH.
    @param _toAddress The address to whom to transfer ETH.
    @param _index Index of the borrow
    **/

    function withDraw(
        address _toAddress,
        uint64 _index
    ) external payable nonReentrant whenNotPaused(IMultiSign.Functions(1)){
        // check is _toAddress in not a zero address and isContract address
        require(_toAddress != address(0) && isContract(_toAddress) != true, "To address cannot be a zero and contract address");
        uint64 _ethPrice = uint64(getUSDValue());

        calculateRatio(0,_ethPrice);
        lastEthprice = uint128(_ethPrice);

        ITreasury.GetBorrowingResult memory getBorrowingResult = treasury.getBorrowing(msg.sender,_index);
        ITreasury.DepositDetails memory depositDetail = getBorrowingResult.depositDetails;
        IGlobalVariables.OmniChainData memory omniChainData = globalVariables.getOmniChainData();

        // check if borrowerIndex in BorrowerDetails of the msg.sender is greater than or equal to Index
        if(getBorrowingResult.totalIndex >= _index ) {
            // Check if user amount in the Index is been liquidated or not
            require(!depositDetail.liquidated,"User amount has been liquidated");
            // check if withdrawed in depositDetail in borrowing of msg.seader is false or not
            if(depositDetail.withdrawed == false) {                                  
                // Calculate the borrowingHealth
                uint128 borrowingHealth = BorrowLib.calculateEthPriceRatio(depositDetail.ethPriceAtDeposit,_ethPrice);
                require(borrowingHealth > 8000,"BorrowingHealth is Low");
                // Calculate th borrower's debt
                uint256 borrowerDebt = BorrowLib.calculateDebtAmount(depositDetail.normalizedAmount, lastCumulativeRate);
                calculateCumulativeRate();
                lastEventTime = uint128(block.timestamp);
                // Check whether the Borrower have enough Trinty
                require(usda.balanceOf(msg.sender) >= borrowerDebt, "User balance is less than required");
                            
                // Update the borrower's data
                {depositDetail.ethPriceAtWithdraw = _ethPrice;
                depositDetail.withdrawed = true;
                depositDetail.withdrawTime = uint64(block.timestamp);
                // Calculate interest for the borrower's debt
                //uint256 interest = borrowerDebt - depositDetail.borrowedAmount;

                uint256 discountedETH = BorrowLib.calculateDiscountedETH(depositDetail.depositedAmount,_ethPrice); // 0.4
                omniChainData.abondUSDaPool += discountedETH;
                treasury.updateAbondUSDaPool(discountedETH,true);
                // Calculate the amount of USDa to burn and sent to the treasury
                // uint256 halfValue = (50 *(depositDetail.borrowedAmount))/100;
                //!console.log("BORROWED AMOUNT",depositDetail.borrowedAmount);
                //!console.log("DISCOUNTED ETH",discountedETH);
                uint256 burnValue = depositDetail.borrowedAmount - discountedETH;
                //!console.log("BURN VALUE",burnValue);
                // Burn the USDa from the Borrower
                bool success = usda.burnFromUser(msg.sender, burnValue);
                if(!success){
                    revert Borrowing_WithdrawBurnFailed();
                }

                //Transfer the remaining USDa to the treasury
                bool transfer = usda.transferFrom(msg.sender,treasuryAddress,borrowerDebt - burnValue);
                if(!transfer){
                    revert Borrowing_WithdrawUSDaTransferFailed();
                }
                //Update totalNormalizedAmount
                totalNormalizedAmount -= depositDetail.normalizedAmount;
                omniChainData.normalizedAmount -= depositDetail.normalizedAmount;
                //!console.log("borrowerDebt",borrowerDebt);
                omniChainData.totalInterest += borrowerDebt - depositDetail.borrowedAmount;
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
                        omniChainData.ethRemainingInWithdraw += (ethToReturn - depositDetail.depositedAmount);
                    }else{
                        ethRemainingInWithdraw += (depositDetail.depositedAmount - ethToReturn);
                        omniChainData.ethRemainingInWithdraw += (depositDetail.depositedAmount - ethToReturn);
                    }
                    ethValueRemainingInWithdraw += (ethRemainingInWithdraw * _ethPrice);
                    omniChainData.ethValueRemainingInWithdraw += (ethRemainingInWithdraw * _ethPrice);
                }else if(borrowingHealth == 10000){
                    ethToReturn = depositedAmountvalue;
                }else if(8000 < borrowingHealth && borrowingHealth < 10000) {
                    ethToReturn = depositDetail.depositedAmount;
                }else{
                    revert("BorrowingHealth is Low");
                }
                ethToReturn = BorrowLib.calculateHalfValue(ethToReturn);

                bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
                //! calculting fee 
                MessagingFee memory fee = globalVariables.quote(IGlobalVariables.FunctionToDo(1), _options, false);
                --omniChainData.noOfBorrowers;
                omniChainData.totalVolumeOfBorrowersAmountinWei += depositDetail.depositedAmount;
                omniChainData.totalVolumeOfBorrowersAmountinUSD += depositDetail.depositedAmountUsdValue;

                globalVariables.setOmniChainData(omniChainData);

                // Call withdraw in treasury
                bool sent = treasury.withdraw(msg.sender,_toAddress,ethToReturn,_index);
                if(!sent){
                    revert Borrowing_WithdrawEthTransferFailed();
                }

                //! Calling Omnichain send function
                globalVariables.send{value:fee.nativeFee}(IGlobalVariables.FunctionToDo(1), fee, _options,msg.sender);
                emit Withdraw(msg.sender,_index,block.timestamp,ethToReturn,depositDetail.aBondTokensAmount,borrowerDebt);
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
        return (BorrowLib.redeemYields(user, aBondAmount, address(usda), address(abond), address(treasury)));
    }

    function getAbondYields(address user,uint128 aBondAmount) public view returns(uint128,uint256,uint256){
        return (BorrowLib.getAbondYields(user, aBondAmount, address(abond), address(treasury)));
    }

    /**
     * @dev This function liquidate ETH which are below downside protection.
     * @param user The address to whom to liquidate ETH.
     * @param index Index of the borrow
     */

    function liquidate(
        address user,
        uint64 index
    ) external payable whenNotPaused(IMultiSign.Functions(2)) onlyAdmin{

        // Check whether the liquidator 
        require(user != address(0), "To address cannot be a zero address");
        require(msg.sender != user,"You cannot liquidate your own assets!");

        calculateCumulativeRate();
        bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250000, 0);

        MessagingFee memory fee = globalVariables.quote(IGlobalVariables.FunctionToDo(2), _options, false);
        
        ++noOfLiquidations;

        (CDSInterface.LiquidationInfo memory liquidationInfo ) = borrowLiquiation.liquidateBorrowPosition{value: msg.value - fee.nativeFee}(
            user,
            index,
            uint64(getUSDValue()),
            lastCumulativeRate
        );

        //! Calling Omnichain send function
        globalVariables.sendForLiquidation{value:fee.nativeFee}(
            IGlobalVariables.FunctionToDo(2), 
            noOfLiquidations,
            liquidationInfo, 
            fee, 
            _options,
            msg.sender);

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

    function setBondRatio(uint64 _bondRatio) external onlyAdmin {
        require(_bondRatio != 0, "Bond Ratio can't be zero");
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(7)));
        bondRatio = _bondRatio;
    }

    function getLTV() public view returns(uint8){
        return LTV;
    }

    // function getLastEthVaultValue() public view returns(uint256){
    //     return (lastEthVaultValue/100);
    // }

    /**
     * @dev update the last eth vault value
     * @param _amount eth vault value
     */
    function updateLastEthVaultValue(uint256 _amount) external onlyTreasury{
        require(_amount != 0,"Last ETH vault value can't be zero");
        IGlobalVariables.OmniChainData memory omniChainData = globalVariables.getOmniChainData();
        omniChainData.ethVaultValue += _amount;
        globalVariables.setOmniChainData(omniChainData);
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

        IGlobalVariables.OmniChainData memory omniChainData = globalVariables.getOmniChainData();

        (uint64 ratio, IGlobalVariables.OmniChainData memory omniChainDataFromLib) = BorrowLib.calculateRatio(
            _amount,
            currentEthPrice,
            lastEthprice,
            omniChainData.noOfBorrowers,
            omniChainData.totalCdsDepositedAmount,
            omniChainData  //! using global data instead of individual chain data
            );

        //! updating global data 
        globalVariables.setOmniChainData(omniChainDataFromLib);

        return ratio;
    }

    function setAPR(uint8 _APR, uint128 _ratePerSec) external whenNotPaused(IMultiSign.Functions(3)) onlyAdmin{
        require(_ratePerSec != 0 && _APR != 0,"Rate should not be zero");
        require(multiSign.executeSetterFunction(IMultiSign.SetterFunctions(1)));
        APR = _APR;
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

    function updateRatePerSecByUSDaPrice(uint32 usdaPrice) public onlyAdmin{
        if(usdaPrice <= 0) revert("Invalid USDa price");
        (ratePerSec, APR) = BorrowLib.calculateNewAPRToUpdate(usdaPrice);
    }
}