// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interface/ITrinityToken.sol";
import "../interface/IBorrowing.sol";
import "../interface/AaveInterfaces/IWETHGateway.sol";
import "../interface/AaveInterfaces/IPoolAddressesProvider.sol";
import "../interface/ICEther.sol";
import "hardhat/console.sol";

interface IATOKEN is IERC20{}

contract Treasury is Ownable{

    error Treasury_ZeroDeposit();
    error Treasury_ZeroWithdraw();
    error Treasury_AavePoolAddressZero();
    error Treasury_AaveDepositAndMintFailed();
    error Treasury_AaveWithdrawFailed();
    error Treasury_CompoundDepositAndMintFailed();
    error Treasury_CompoundWithdrawFailed();
    error Treasury_EthTransferToCdsFailed();

    IBorrowing public borrow;
    ITrinityToken public trinity;
    IWrappedTokenGatewayV3 public wethGateway;
    IPoolAddressesProvider public aavePoolAddressProvider;
    IATOKEN public aToken;
    ICEther public cEther;

    address public borrowingContract;
    address public cdsContract;  
    address public compoundAddress;
    address public aaveWETH;        //wethGateway Address for Approve

    //Depositor's Details for each depsoit.
    struct DepositDetails{
        uint64 depositedTime;
        uint128 depositedAmount;
        uint64 downsidePercentage;
        uint128 ethPriceAtDeposit;
        uint128 borrowedAmount;
        uint128 normalizedAmount;
        uint8 withdrawNo;
        bool withdrawed;
        uint128 withdrawAmount;
        bool liquidated;
        uint64 ethPriceAtWithdraw;
        uint64 withdrawTime;
        uint128 pTokensAmount;
    }

    //Borrower Details
    struct BorrowerDetails {
        uint256 depositedAmount;
        mapping(uint64 => DepositDetails) depositDetails;
        uint256 totalBorrowedAmount;
        bool hasBorrowed;
        bool hasDeposited;
        //uint64 downsidePercentage;
        //uint128 ETHPrice;
        //uint64 depositedTime;
        uint64 borrowerIndex;
        uint128 totalPTokens;
    }

    //Each Deposit to Aave/Compound
    struct EachDepositToProtocol{
        uint64 depositedTime;
        uint128 depositedAmount;
        uint128 ethPriceAtDeposit;
        uint256 depositedUsdValue;
        uint128 tokensCredited;

        bool withdrawed;
        uint128 ethPriceAtWithdraw;
        uint64 withdrawTime;
        uint256 withdrawedUsdValue;
    }

    //Total Deposit to Aave/Compound
    struct ProtocolDeposit{
        mapping (uint64 => EachDepositToProtocol) eachDepositToProtocol;
        uint64 depositIndex;
        uint256 depositedAmount;
        uint256 totalCreditedTokens;
        uint256 depositedUsdValue;       
    }

    enum Protocol{Aave,Compound}

    mapping(address depositor => BorrowerDetails) public borrowing;
    mapping(Protocol => ProtocolDeposit) public protocolDeposit;
    uint256 public totalVolumeOfBorrowersAmountinWei;
    uint256 public totalVolumeOfBorrowersAmountinUSD;
    uint128 public noOfBorrowers;
    uint256 public totalInterest;
    uint256 public totalInterestFromLiquidation;

    event Deposit(address indexed user,uint256 amount);
    event Withdraw(address indexed user,uint256 amount);
    event DepositToAave(uint64 count,uint256 amount);
    event WithdrawFromAave(uint64 count,uint256 amount);
    event DepositToCompound(uint64 count,uint256 amount);
    event WithdrawFromCompound(uint64 count,uint256 amount);


    constructor(
        address _borrowing,
        address _tokenAddress,
        address _cdsContract,
        address _wethGateway,
        address _cEther,
        address _aavePoolAddressProvider,
        address _aToken
        ) {
            borrowingContract = _borrowing;
            cdsContract = _cdsContract;
            borrow = IBorrowing(_borrowing);
            trinity = ITrinityToken(_tokenAddress);
            wethGateway = IWrappedTokenGatewayV3(_wethGateway);       //0xD322A49006FC828F9B5B37Ab215F99B4E5caB19C
            cEther = ICEther(_cEther);                                //0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5
            compoundAddress = _cEther;
            aavePoolAddressProvider = IPoolAddressesProvider(_aavePoolAddressProvider);  //0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e
            aToken = IATOKEN(_aToken);                                                   //0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8
            aaveWETH = _wethGateway;
    }

    modifier onlyBorrowingContract() {
        require( msg.sender == borrowingContract, "This function can only called by borrowing contract");
        _;
    }
    modifier onlyCDSContract() {
        require( msg.sender == cdsContract, "This function can only called by CDS contract");
        _;
    }

    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    /**
     * @dev This function takes ethPrice, depositTime parameters to deposit eth into the contract and mint them back the Trinity tokens.
     * @param _ethPrice get current eth price 
     * @param _depositTime get unixtime stamp at the time of deposit
     **/

    function deposit(
        address user,
        uint128 _ethPrice,
        uint64 _depositTime
        )
        external payable onlyBorrowingContract returns(bool,uint64) {

        uint64 borrowerIndex;
        //check if borrower is depositing for the first time or not
        if (!borrowing[user].hasDeposited) {
            //change borrowerindex to 1
            borrowerIndex = borrowing[user].borrowerIndex = 1;
          
            //change hasDeposited bool to true after first deposit
            borrowing[user].hasDeposited = true;
            ++noOfBorrowers;
        }
        else {
            //increment the borrowerIndex for each deposit
            borrowerIndex = ++borrowing[user].borrowerIndex;
            // borrowerIndex = borrowing[user].borrowerIndex;
        }
    
        // update total deposited amount of the user
        borrowing[user].depositedAmount += msg.value;

        // update deposited amount of the user
        borrowing[user].depositDetails[borrowerIndex].depositedAmount = uint128(msg.value);

        //Total volume of borrowers in USD
        totalVolumeOfBorrowersAmountinUSD += (_ethPrice * msg.value);

        //Total volume of borrowers in Wei
        totalVolumeOfBorrowersAmountinWei += msg.value;

        //Adding depositTime to borrowing struct
        borrowing[user].depositDetails[borrowerIndex].depositedTime = _depositTime;

        //Adding ethprice to struct
        borrowing[user].depositDetails[borrowerIndex].ethPriceAtDeposit = _ethPrice;
        
        emit Deposit(user,msg.value);
        return (borrowing[user].hasDeposited,borrowerIndex);
    }

    function withdraw(address borrower,address toAddress,uint256 _amount,uint64 index,uint64 _ethPrice) external onlyBorrowingContract returns(bool){
        // Check the _amount is non zero
        require(_amount > 0, "Cannot withdraw zero Ether");
        require(borrowing[borrower].depositDetails[index].withdrawNo > 0,"");
        uint256 amount = (_amount *50)/100;
        // Send the ETH to Borrower
        (bool sent,) = payable(toAddress).call{value: amount}("");
        require(sent, "Failed to send Ether");
        if(borrowing[borrower].depositDetails[index].withdrawNo == 1){
            borrowing[borrower].totalBorrowedAmount -= borrowing[borrower].depositDetails[index].borrowedAmount;
        }
        borrowing[borrower].depositDetails[index].withdrawAmount += uint128(amount);
        totalVolumeOfBorrowersAmountinUSD -= (_ethPrice * amount);
        totalVolumeOfBorrowersAmountinWei -= amount;
        emit Withdraw(toAddress,_amount);
        return true;
    }

    /**
     * @dev This function depsoit 25% of the deposited ETH to AAVE and mint aTokens 
    */

    function depositToAave() external onlyBorrowingContract{

        //Divide the Total ETH in the contract to 1/4
        uint256 share = ((address(this).balance)*25)/100;

        //Check the amount to be deposited is greater than zero
        if(share == 0){
            revert Treasury_ZeroDeposit();
        }

        address poolAddress = aavePoolAddressProvider.getPool();

        if(poolAddress == address(0)){
            revert Treasury_AavePoolAddressZero();
        }

        // Call the deposit function in aave to deposit eth.
        wethGateway.depositETH{value: share}(poolAddress,address(this),0);

        uint256 creditedAmount = aToken.balanceOf(address(this));
        if(creditedAmount == protocolDeposit[Protocol.Aave].totalCreditedTokens){
            revert Treasury_AaveDepositAndMintFailed();
        }

        uint64 count = protocolDeposit[Protocol.Aave].depositIndex;
        count += 1;

        //Assign depositIndex(number of times deposited)
        protocolDeposit[Protocol.Aave].depositIndex = count;

        //Update the total amount deposited in Aave
        protocolDeposit[Protocol.Aave].depositedAmount += share;

        //Update the deposited time
        protocolDeposit[Protocol.Aave].eachDepositToProtocol[count].depositedTime = uint64(block.timestamp);

        //Update the deposited amount
        protocolDeposit[Protocol.Aave].eachDepositToProtocol[count].depositedAmount = uint128(share);

        //Update the deposited amount in USD
        uint128 ethPrice = protocolDeposit[Protocol.Aave].eachDepositToProtocol[count].ethPriceAtDeposit = uint128(borrow.getUSDValue());
        protocolDeposit[Protocol.Aave].eachDepositToProtocol[count].depositedUsdValue = share * ethPrice;

        //Update the total deposited amount in USD
        protocolDeposit[Protocol.Aave].depositedUsdValue = protocolDeposit[Protocol.Aave].depositedAmount * ethPrice;

        protocolDeposit[Protocol.Aave].eachDepositToProtocol[count].tokensCredited = uint128(creditedAmount) - uint128(protocolDeposit[Protocol.Aave].totalCreditedTokens);
        protocolDeposit[Protocol.Aave].totalCreditedTokens = creditedAmount;

        emit DepositToAave(count,share);
    }

    /**
     * @dev This function withdraw ETH from AAVE.
     * @param amount amount of ETH to withdraw 
     */

    function withdrawFromAave(uint64 index,uint256 amount) external onlyBorrowingContract{

        //Check the amount to be withdraw is greater than zero
        if(amount == 0){
            revert Treasury_ZeroWithdraw();
        }

        //Check the deposited amount in the given index is already withdrawed
        require(!protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].withdrawed,"Already withdrawed in this index");

        address poolAddress = aavePoolAddressProvider.getPool();

        if(poolAddress == address(0)){
            revert Treasury_AavePoolAddressZero();
        }

        aToken.approve(aaveWETH,amount);

        // Call the withdraw function in aave to withdraw eth.
        wethGateway.withdrawETH(poolAddress,amount,address(this));

        uint256 aaveToken = cEther.balanceOf(address(this));
        if(aaveToken == protocolDeposit[Protocol.Aave].totalCreditedTokens){
            revert Treasury_AaveWithdrawFailed();
        }

        //Update the total amount deposited in Aave
        protocolDeposit[Protocol.Aave].depositedAmount -= amount;

        //Set withdrawed to true
        protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].withdrawed = true;

        //Update the withdraw time
        protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].withdrawTime = uint64(block.timestamp);

        //Update the withdrawed amount in USD
        uint128 ethPrice = protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].ethPriceAtWithdraw = uint64(borrow.getUSDValue());
        protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].withdrawedUsdValue = amount * ethPrice;

        //Update the total deposited amount in USD
        protocolDeposit[Protocol.Aave].depositedUsdValue = protocolDeposit[Protocol.Aave].depositedAmount * ethPrice;

        protocolDeposit[Protocol.Aave].totalCreditedTokens -= amount; 

        emit WithdrawFromAave(index,amount);
    }

    /**
     * @dev This function depsoit 25% of the deposited ETH to COMPOUND and mint cETH. 
    */

    function depositToCompound() external onlyBorrowingContract{

        //Divide the Total ETH in the contract to 1/4
        uint256 share = ((address(this).balance)*25)/100;

        //Check the amount to be deposited is greater than zero       
        if(share == 0){
            revert Treasury_ZeroDeposit();
        }

        // Call the deposit function in Coumpound to deposit eth.
        cEther.mint{value: share}();

        uint256 creditedAmount = cEther.balanceOf(address(this));

        if(creditedAmount == protocolDeposit[Protocol.Compound].totalCreditedTokens){
            revert Treasury_CompoundDepositAndMintFailed();
        }

        uint64 count = protocolDeposit[Protocol.Compound].depositIndex;
        count += 1;

        //Assign depositIndex(number of times deposited)
        protocolDeposit[Protocol.Compound].depositIndex = count;

        //Update the total amount deposited in Compound
        protocolDeposit[Protocol.Compound].depositedAmount += share;

        //Update the deposited time
        protocolDeposit[Protocol.Compound].eachDepositToProtocol[count].depositedTime = uint64(block.timestamp);

        //Update the deposited amount
        protocolDeposit[Protocol.Compound].eachDepositToProtocol[count].depositedAmount = uint128(share);

        //Update the deposited amount in USD
        uint128 ethPrice = protocolDeposit[Protocol.Compound].eachDepositToProtocol[count].ethPriceAtDeposit = uint128(borrow.getUSDValue());
        protocolDeposit[Protocol.Compound].eachDepositToProtocol[count].depositedUsdValue = share * ethPrice;

        //Update the total deposited amount in USD
        protocolDeposit[Protocol.Compound].depositedUsdValue = protocolDeposit[Protocol.Compound].depositedAmount * ethPrice;

        protocolDeposit[Protocol.Compound].eachDepositToProtocol[count].tokensCredited = uint128(creditedAmount) - uint128(protocolDeposit[Protocol.Compound].totalCreditedTokens);
        protocolDeposit[Protocol.Compound].totalCreditedTokens = creditedAmount;

        emit DepositToCompound(count,share);
    }

    /**
     * @dev This function withdraw ETH from COMPOUND.
     */

    function withdrawFromCompound(uint64 index) external onlyBorrowingContract{

        uint256 amount = protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].tokensCredited;

        //Check the deposited amount in the given index is already withdrawed
        require(!protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].withdrawed,"Already withdrawed in this index");

        //Check the amount to be withdraw is greater than zero
        if(amount == 0){
            revert Treasury_ZeroWithdraw();
        }

        // Call the redeem function in Compound to withdraw eth.
        cEther.redeem(amount);
        uint256 cToken = cEther.balanceOf(address(this));
        if(cToken == protocolDeposit[Protocol.Compound].totalCreditedTokens){
            revert Treasury_CompoundWithdrawFailed();
        }

        //Update the total amount deposited in Coumpound
        protocolDeposit[Protocol.Compound].depositedAmount -= amount;

        //Set withdrawed to true
        protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].withdrawed = true;

        //Update the withdraw time
        protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].withdrawTime = uint64(block.timestamp);

        //Update the withdraw amount in USD
        uint128 ethPrice = protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].ethPriceAtWithdraw = uint128(borrow.getUSDValue());
        protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].withdrawedUsdValue = amount * ethPrice;

        //Update the total deposited amount in USD
        protocolDeposit[Protocol.Compound].depositedUsdValue = protocolDeposit[Protocol.Compound].depositedAmount * ethPrice;

        protocolDeposit[Protocol.Compound].totalCreditedTokens -= amount;
        protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].tokensCredited = 0;

        emit WithdrawFromCompound(index,amount);
    }


    // function getUserAccountData (address user) external view returns (BorrowerDetails memory){
    //     DepositDetails memory depositorAccountData;
    //     depositorAccountData = borrowing[user];
    //     return depositorAccountData;
    // }


    function setBorrowingContract(address _address) external onlyOwner {
        require(_address != address(0) && isContract(_address) != false, "Input address is invalid");
        borrowingContract = _address;
        borrow = IBorrowing(_address);
    }

    function getBalanceInTreasury() external view returns(uint256){
        return address(this).balance;
    }

    function updateDepositDetails(address depositor,uint64 index,DepositDetails memory depositDetail) external {
            borrowing[depositor].depositDetails[index] = depositDetail;
    }

    function updateHasBorrowed(address borrower,bool _bool) external {
        borrowing[borrower].hasBorrowed = _bool;
    }
    function updateTotalDepositedAmount(address borrower,uint128 amount) external {
        borrowing[borrower].depositedAmount -= amount;
    }
    function updateTotalBorrowedAmount(address borrower,uint256 amount) external {
        borrowing[borrower].totalBorrowedAmount += amount;
    }
    function updateTotalPTokensIncrease(address borrower,uint128 amount) external {
        borrowing[borrower].totalPTokens += amount;
    }
    function updateTotalPTokensDecrease(address borrower,uint128 amount) external {
        borrowing[borrower].totalPTokens -= amount;
    }

    function updateTotalInterest(uint _amount) external{
        totalInterest = _amount;
    }
    function updateTotalInterestFromLiquidation(uint _amount) external{
        totalInterestFromLiquidation = _amount;
    }

    function getBorrowing(address depositor,uint64 index) external view returns(uint64,DepositDetails memory){
        return (
            borrowing[depositor].borrowerIndex,
            borrowing[depositor].depositDetails[index]);
    }

    function approval(address _address, uint _amount) external onlyCDSContract{
        require(_address != address(0) && _amount != 0, "Input address or amount is invalid");
        bool state = trinity.approve(_address, _amount);
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
        bool sent = trinity.transfer(toAddress,amount);
        require(sent, "Failed to send Ether");
    }

    function transferEthToCds(address borrower,uint64 index) external onlyBorrowingContract{
        (bool sent,) = payable(cdsContract).call{value: borrowing[borrower].depositDetails[index].depositedAmount}("");
        if(!sent){
            revert Treasury_EthTransferToCdsFailed();
        }
    }

    receive() external payable{}
}