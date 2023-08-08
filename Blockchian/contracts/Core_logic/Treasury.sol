// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interface/IBorrowing.sol";
import "../interface/IWETHGateway.sol";
import "../interface/ICEther.sol";

contract Treasury is Ownable{

    IBorrowing public borrowing;
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

    struct ToAave{
        uint64 depositedTime;
        bool hasDeposited;
        uint128 depositedAmount;
        uint64 ethPriceAtDeposit;
        uint64 depositedUsdValue;
    }

    mapping(address depositor => BorrowerDetails) public borrowing;
    mapping (uint256 count => ToAave) public toAave;
    uint256 public aaveCount;
    uint128 public totalVolumeOfBorrowersinWei;
    uint128 public totalVolumeOfBorrowersinUSD;

    event Deposit(address indexed user,uint256 amount);
    event Withdraw(address indexed user,uint256 amount);
    event DepositToAave(uint256 amount);
    event WithdrawFromAave(uint256 amount);
    event DepositToCompound(uint256 amount);
    event WithdrawFromCompound(uint256 amount);


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

    function deposit( address user,uint64 _ethPrice,uint64 _depositTime) external payable {
        require(msg.value > 0, "Cannot deposit zero tokens");
        require(user.balance > 0, "You do not have sufficient balance to execute this transaction");

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
           // borroweIndex = borrowing[user].borrowerIndex;
        }
    
        // update total deposited amount of the user
        borrowing[user].depositedAmount += msg.value;

        // update deposited amount of the user
        borrowing[user].depositDetails[borrowerIndex].depositedAmount = uint128(msg.value);

        //Total volume of borrowers in USD
        totalVolumeOfBorrowersinUSD += (uint128(ethPrice) * uint128(msg.value));

        //Total volume of borrowers in Wei
        totalVolumeOfBorrowersinWei += uint128(msg.value);

        borrowing[user].depositDetails[borrowerIndex].depositedAmount =  uint128(msg.value);

        //Adding depositTime to borrowing struct
        borrowing[user].depositDetails[borrowerIndex].depositedTime = _depositTime;

        //Adding ethprice to struct
        borrowing[user].depositDetails[borrowerIndex].ethPriceAtDeposit = _ethPrice;
        
        //call transfer function of trinity token
        borrowing.transferToken(user,borrowerIndex);

        emit Deposit(user,msg.value);
    }

    function withdraw(address toAddress,uint256 _amount) external {
        require(_amount > 0, "Cannot withdraw zero Ether");
        require(totalETH >= _amount,"Insufficient balance in Treasury");
        require(depositorDetails[toAddress].hasDeposited,"Not a Depositor");

        depositorDetails[toAddress].depositedTime = block.timestamp;
        depositorDetails[toAddress].depositedAmount -= _amount;
        uint256 depositedAmount = depositorDetails[toAddress].depositedAmount;
        depositorDetails[toAddress].ethPriceAtWithdraw = borrow.getUSDValue();
        depositorDetails[toAddress].depositedUsdValue = depositedAmount * depositorDetails[toAddress].ethPriceAtWithdraw;

        if(depositedAmount == 0){
            depositorDetails[toAddress].hasDeposited = false;
        }

        (bool sent,) = toAddress.call{value: _amount}("");
        require(sent, "Failed to send ether");

        depositorDetails[toAddress].withdrawTime = block.timestamp;
        depositorDetails[toAddress].withdrawed = true;

        emit Withdraw(toAddress,_amount);
    }

    /**
     * @dev This function depsoit 25% of the deposited ETH to AAVE and mint aTokens 
    */

    function depositToAave() external onlyOwner{
        uint256 share = (address(this).balance)/4;
        require(share > 0,"Null deposit");
        wethGateway.depositETH{value: share}(ethAddress,address(this),0);
        aaveCount += 1;

        toAave[aaveCount].depositedTime = block.timestamp;
        toAave[aaveCount].hasDeposited = true;
        toAave[aaveCount].depositedAmount += share;
        uint256 depositedAmount = toAave[aaveCount].depositedAmount;
        toAave[aaveCount].ethPriceAtDeposit = borrow.getUSDValue();
        toAave[aaveCount].depositedUsdValue = depositedAmount * toAave[aaveCount].ethPriceAtDeposit;

        emit DepositToAave(share);
    }

    /**
     * @dev This function withdraw ETH from AAVE.
     * @param amount amount of ETH to withdraw 
     */

    function withdrawFromAave(uint256 amount) external onlyOwner{
        require(amount > 0,"Null withdraw");
        wethGateway.withdrawETH(ethAddress,amount,address(this));

        emit WithdrawFromAave(amount);
    }

    /**
     * @dev This function depsoit 25% of the deposited ETH to COMPOUND and mint cETH. 
    */

    function depositToCompound() external onlyOwner{
        uint256 share = (address(this).balance)/4;
        require(share > 0,"Null deposit");
        cEther.mint{value: share};

        emit DepositToCompound(share);
    }

    /**
     * @dev This function withdraw ETH from COMPOUND.
     * @param amount amount of ETH to withdraw 
     */

    function withdrawFromCompound(uint256 amount) external onlyOwner{
        require(amount > 0,"Null withdraw");
        cEther.redeem(amount);
        emit WithdrawFromCompound(amount);
    }
    /**
     * @dev This function returns the user data in protocol
     * @param user address of the user for whom to get the data
     */
    function getUserAccountData (address user) external view returns (DepositorDetails){
        DepositorDetails memory depositorAccountData;
        depositorAccountData = depositorDetails[user];
        return depositorAccountData;
    }

}