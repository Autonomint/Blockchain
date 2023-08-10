// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interface/IBorrowing.sol";
import "../interface/IWETHGateway.sol";
import "../interface/ICEther.sol";

contract Treasury is Ownable{

    IBorrowing public borrow;
    IWrappedTokenGatewayV3 public wethGateway;
    ICEther public cEther;

    address constant ethAddress = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    //Depositor's Details for each depsoit.
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

    //Borrower Details
    struct BorrowerDetails {
        uint256 depositedAmount;
        mapping(uint64 => DepositDetails) depositDetails;
        uint256 borrowedAmount;
        bool hasBorrowed;
        bool hasDeposited;
        //uint64 downsidePercentage;
        //uint128 ETHPrice;
        //uint64 depositedTime;
        uint64 borrowerIndex;
    }

    //Each Deposit to Aave/Compound
    struct EachDepositToProtocol{
        uint64 depositedTime;
        uint128 depositedAmount;
        uint64 ethPriceAtDeposit;
        uint128 depositedUsdValue;

        bool withdrawed;
        uint64 ethPriceAtWithdraw;
        uint64 withdrawTime;
        uint64 withdrawedUsdValue;
    }

    //Total Deposit to Aave/Compound
    struct ProtocolDeposit{
        mapping (uint64 => EachDepositToProtocol) eachDepositToProtocol;
        uint64 depositIndex;
        uint256 depositedAmount;
        uint128 depositedUsdValue;       
    }

    enum Protocol{Aave,Compound}

    mapping(address depositor => BorrowerDetails) public borrowing;
    mapping(Protocol => ProtocolDeposit) public protocolDeposit;
    uint128 public totalVolumeOfBorrowersinWei;
    uint128 public totalVolumeOfBorrowersinUSD;

    event Deposit(address indexed user,uint256 amount);
    event Withdraw(address indexed user,uint256 amount);
    event DepositToAave(uint64 count,uint256 amount);
    event WithdrawFromAave(uint64 count,uint256 amount);
    event DepositToCompound(uint64 count,uint256 amount);
    event WithdrawFromCompound(uint64 count,uint256 amount);


    constructor(address _borrowing,address _wethGateway,address _cEther) {
        borrow = IBorrowing(_borrowing);
        wethGateway = IWrappedTokenGatewayV3(_wethGateway);       //0xD322A49006FC828F9B5B37Ab215F99B4E5caB19C
        cEther = ICEther(_cEther);                                //0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5
    }

    /**
     * @dev This function takes ethPrice, depositTime parameters to deposit eth into the contract and mint them back the Trinity tokens.
     * @param _ethPrice get current eth price 
     * @param _depositTime get unixtime stamp at the time of deposit
     **/

    function deposit(
        address user,
        uint64 _ethPrice,
        uint64 _depositTime
        )
        external payable onlyOwner returns(uint64,bool) {

        uint64 borrowerIndex;
        //check if borrower is depositing for the first time or not
        if (!borrowing[user].hasDeposited) {
            //change borrowerindex to 1
            borrowerIndex = borrowing[user].borrowerIndex = 1;
          
            //change hasDeposited bool to true after first deposit
            borrowing[user].hasDeposited = true;
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
        totalVolumeOfBorrowersinUSD += (uint128(_ethPrice) * uint128(msg.value));

        //Total volume of borrowers in Wei
        totalVolumeOfBorrowersinWei += uint128(msg.value);

        //Adding depositTime to borrowing struct
        borrowing[user].depositDetails[borrowerIndex].depositedTime = _depositTime;

        //Adding ethprice to struct
        borrowing[user].depositDetails[borrowerIndex].ethPriceAtDeposit = _ethPrice;
        
        emit Deposit(user,msg.value);
        return (
            borrowerIndex,
            borrowing[user].hasDeposited
            );
    }

    function withdraw(address toAddress,uint256 _amount) external {
        require(_amount > 0, "Cannot withdraw zero Ether");

        // if(depositedAmount == 0){
        //     depositorDetails[toAddress].hasDeposited = false;
        // }

        // (bool sent,) = toAddress.call{value: _amount}("");
        // require(sent, "Failed to send ether");

        emit Withdraw(toAddress,_amount);
    }

    /**
     * @dev This function depsoit 25% of the deposited ETH to AAVE and mint aTokens 
    */

    function depositToAave() external onlyOwner{

        //Divide the Total ETH in the contract to 1/4
        uint256 share = (address(this).balance)/4;

        //Check the amount to be deposited is greater than zero
        require(share > 0,"Null deposit");

        // Call the deposit function in aave to deposit eth.
        wethGateway.depositETH{value: share}(ethAddress,address(this),0);

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
        uint64 ethPrice = protocolDeposit[Protocol.Aave].eachDepositToProtocol[count].ethPriceAtDeposit = uint64(borrow.getUSDValue());
        protocolDeposit[Protocol.Aave].eachDepositToProtocol[count].depositedUsdValue = uint128(share) * uint128(ethPrice);

        //Update the total deposited amount in USD
        protocolDeposit[Protocol.Aave].depositedUsdValue = uint128(protocolDeposit[Protocol.Aave].depositedAmount) * uint128(ethPrice);

        emit DepositToAave(count,share);
    }

    /**
     * @dev This function withdraw ETH from AAVE.
     * @param amount amount of ETH to withdraw 
     */

    function withdrawFromAave(uint64 index,uint256 amount) external onlyOwner{

        //Check the amount to be withdraw is greater than zero
        require(amount > 0,"Null withdraw");

        //Check the deposited amount in the given index is already withdrawed
        require(!protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].withdrawed,"Already withdrawed in this index");

        // Call the withdraw function in aave to withdraw eth.
        wethGateway.withdrawETH(ethAddress,amount,address(this));

        //Update the total amount deposited in Aave
        protocolDeposit[Protocol.Aave].depositedAmount -= amount;

        //Set withdrawed to true
        protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].withdrawed = true;

        //Update the withdraw time
        protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].withdrawTime = uint64(block.timestamp);

        //Update the withdrawed amount in USD
        uint64 ethPrice = protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].ethPriceAtWithdraw = uint64(borrow.getUSDValue());
        protocolDeposit[Protocol.Aave].eachDepositToProtocol[index].withdrawedUsdValue = uint64(amount) * ethPrice;

        //Update the total deposited amount in USD
        protocolDeposit[Protocol.Aave].depositedUsdValue = uint128(protocolDeposit[Protocol.Aave].depositedAmount) * uint128(ethPrice);

        emit WithdrawFromAave(index,amount);
    }

    /**
     * @dev This function depsoit 25% of the deposited ETH to COMPOUND and mint cETH. 
    */

    function depositToCompound() external onlyOwner{

        //Divide the Total ETH in the contract to 1/4
        uint256 share = (address(this).balance)/4;

        //Check the amount to be deposited is greater than zero       
        require(share > 0,"Null deposit");

        // Call the deposit function in Coumpound to deposit eth.
        cEther.mint{value: share};

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
        uint64 ethPrice = protocolDeposit[Protocol.Compound].eachDepositToProtocol[count].ethPriceAtDeposit = uint64(borrow.getUSDValue());
        protocolDeposit[Protocol.Compound].eachDepositToProtocol[count].depositedUsdValue = uint128(share) * uint128(ethPrice);

        //Update the total deposited amount in USD
        protocolDeposit[Protocol.Compound].depositedUsdValue = uint128(protocolDeposit[Protocol.Compound].depositedAmount) * uint128(ethPrice);

        emit DepositToCompound(count,share);
    }

    /**
     * @dev This function withdraw ETH from COMPOUND.
     * @param amount amount of ETH to withdraw 
     */

    function withdrawFromCompound(uint64 index,uint256 amount) external onlyOwner{

        //Check the amount to be withdraw is greater than zero
        require(amount > 0,"Null withdraw");

        //Check the deposited amount in the given index is already withdrawed
        require(!protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].withdrawed,"Already withdrawed in this index");

        // Call the redeem function in Compound to withdraw eth.
        cEther.redeem(amount);

        //Update the total amount deposited in Coumpound
        protocolDeposit[Protocol.Compound].depositedAmount -= amount;

        //Set withdrawed to true
        protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].withdrawed = true;

        //Update the withdraw time
        protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].withdrawTime = uint64(block.timestamp);

        //Update the withdraw amount in USD
        uint64 ethPrice = protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].ethPriceAtWithdraw = uint64(borrow.getUSDValue());
        protocolDeposit[Protocol.Compound].eachDepositToProtocol[index].withdrawedUsdValue = uint64(amount) * ethPrice;

        //Update the total deposited amount in USD
        protocolDeposit[Protocol.Compound].depositedUsdValue = uint128(protocolDeposit[Protocol.Compound].depositedAmount) * uint128(ethPrice);

        emit WithdrawFromCompound(index,amount);
    }


    // function getUserAccountData (address user) external view returns (BorrowerDetails memory){
    //     DepositDetails memory depositorAccountData;
    //     depositorAccountData = borrowing[user];
    //     return depositorAccountData;
    // }

}