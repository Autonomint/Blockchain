// SPDX-License-Identifier: unlicensed

pragma solidity 0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interface/IBorrowing.sol";
import "../interface/IWETHGateway.sol";

contract Treasury is Ownable{

    IBorrowing public borrowing;
    IWrappedTokenGatewayV3 public wethGateway;

    address constant ethAddress = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // struct DepositDetails{
    //     uint64 depositedTime;
    //     uint128 depositedAmount;
    //     uint64 downsidePercentage;
    //     uint64 ethPriceAtDeposit;
    //     bool withdrawed;
    //     bool liquidated;
    //     uint64 ethPriceAtWithdraw;
    //     uint64 withdrawTime;
    // }

    struct DepositorDetails{
        //mapping (uint256 => DepositDetails) depositDetails;
        uint64 depositedTime;
        bool hasDeposited;
        uint128 depositedAmount;
        uint64 ethPriceAtDeposit;
        uint64 depositedUsdValue;

        bool withdrawed;
        uint64 ethPriceAtWithdraw;
        uint64 withdrawTime;
    }

    //Deposit 25% of ETH to Aave and Compound each
    struct ToOutside{
        uint64 depositedTime;
        bool hasDeposited;
        uint128 depositedAmount;
        uint64 ethPriceAtDeposit;
        uint64 depositedUsdValue;

        bool withdrawed;
        uint64 ethPriceAtWithdraw;
        uint64 withdrawTime;

    }

    mapping (address depositor => DepositorDetails) public depositorDetails;
    mapping (uint256  => ToOutside) public toOutside;
    uint256 public totalETH;

    event Deposit(address indexed user,uint256 amount);
    event Withdraw(address indexed user,uint256 amount);

    constructor(address _borrowing,address _wethGateway) {
        borrowing = IBorrowing(_borrowing);
        wethGateway = IWrappedTokenGatewayV3(_wethGateway);       //0xD322A49006FC828F9B5B37Ab215F99B4E5caB19C
    }

    function deposit(address user) external payable {
        require(msg.value > 0, "Cannot deposit zero tokens");
        require(user.balance > 0, "You do not have sufficient balance to execute this transaction");

        depositorDetails[user].depositedTime = block.timestamp;
        depositorDetails[user].hasDeposited = true;
        depositorDetails[user].depositedAmount += msg.value;
        uint256 depositedAmount = depositorDetails[user].depositedAmount;
        depositorDetails[user].ethPriceAtDeposit = borrowing.getUSDValue();
        depositorDetails[user].depositedUsdValue = depositedAmount * depositorDetails[user].ethPriceAtDeposit;

        totalETH += msg.value;
        emit Deposit(user,msg.value);
    }

    function withdraw(address toAddress,uint256 _amount) external {
        require(_amount > 0, "Cannot withdraw zero Ether");
        require(totalETH >= _amount,"Insufficient balance in Treasury");
        require(depositorDetails[toAddress].hasDeposited,"Not a Depositor");

        depositorDetails[toAddress].depositedTime = block.timestamp;
        depositorDetails[toAddress].depositedAmount -= _amount;
        uint256 depositedAmount = depositorDetails[toAddress].depositedAmount;
        depositorDetails[toAddress].ethPriceAtWithdraw = borrowing.getUSDValue();
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

    function depositToAave() external onlyOwner{
        uint256 share = (address(this).balance)/4;
        require(share > 0,"Null deposit");
        wethGateway.depositETH{value: share}(ethAddress,address(this),0);

        // toOutside[].depositedTime = block.timestamp;
        // toOutside[].hasDeposited = true;
        // toOutside[].depositedAmount += msg.value;

        // uint256 depositedAmount = toOutside[1].depositedAmount;
        // toOutside[].ethPriceAtDeposit = borrowing.getUSDValue();
        // toOutside[].depositedUsdValue = depositedAmount * depositorDetails[1].ethPriceAtDeposit;
    }

    function withdrawFromAave(uint256 amount) external onlyOwner{
        require(amount > 0,"Null withdraw");
        wethGateway.withdrawETH(ethAddress,amount,address(this));
    }

    function getUserAccountData (address user)
        external
        view
        returns(
            uint64 depositedTime,
            bool hasDeposited,
            uint128 depositedAmount,
            uint64 ethPriceAtDeposit,
            uint64 depositedUsdValue,
            bool withdrawed,
            uint64 ethPriceAtWithdraw,
            uint64 withdrawTime)
    {
            // DepositorDetails memory depositorAccountData;
            // depositorAccountData = depositorDetails[user];
            // return depositorAccountData;
    }

}