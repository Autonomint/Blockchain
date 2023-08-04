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
        //uint64 downsidePercentage;
        uint64 ethPriceAtDeposit;
        uint64 depositedUsdValue;

        bool withdrawed;
        uint64 ethPriceAtWithdraw;
        uint64 withdrawTime;
    }

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

    mapping (address => DepositorDetails) public depositorDetails;
    mapping (uint256 => ToOutside) public toOutside;
    uint256 public totalETH;

    // event Deposit(address indexed user,uint256 amount);
    // event Withdraw(address indexed user,uint256 amount);

    constructor(address _borrowing,address _wethGateway) {
        borrowing = IBorrowing(_borrowing);
        wethGateway = IWrappedTokenGatewayV3(_wethGateway);       //0xD322A49006FC828F9B5B37Ab215F99B4E5caB19C
    }

    function deposit() external payable {
        require(msg.value > 0, "Cannot deposit zero tokens");
        require(msg.sender.balance > 0, "You do not have sufficient balance to execute this transaction");

        depositorDetails[msg.sender].depositedTime = block.timestamp;
        depositorDetails[msg.sender].hasDeposited = true;
        depositorDetails[msg.sender].depositedAmount += msg.value;
        //depositorDetails[msg.sender].depositedCount += 1;
        uint256 depositedAmount = depositorDetails[msg.sender].depositedAmount;
        depositorDetails[msg.sender].ethPriceAtDeposit = borrowing.getUSDValue();
        depositorDetails[msg.sender].depositedUsdValue = depositedAmount * depositorDetails[msg.sender].ethPriceAtDeposit;

        totalETH += msg.value;
        emit Deposit(msg.sender,msg.value);
    }

    function withdraw(uint256 _amount) external {
        require(_amount > 0, "Cannot withdraw zero Ether");
        require(totalETH >= _amount,"Insufficient balance in Treasury");
        require(depositorDetails[msg.sender].hasDeposited,"Not a Depositor");

        depositorDetails[msg.sender].depositedTime = block.timestamp;
        depositorDetails[msg.sender].depositedAmount -= _amount;
        //depositorDetails[msg.sender].depositedCount += 1;
        uint256 depositedAmount = depositorDetails[msg.sender].depositedAmount;
        depositorDetails[msg.sender].ethPriceAtWithdraw = borrowing.getUSDValue();
        depositorDetails[msg.sender].depositedUsdValue = depositedAmount * depositorDetails[msg.sender].ethPriceAtWithdraw;

        if(depositedAmount == 0){
            depositorDetails[msg.sender].hasDeposited = false;
        }

        (bool sent,) = msg.sender.call{value: _amount}("");
        require(sent, "Failed to send ether");

        depositorDetails[msg.sender].withdrawTime = block.timestamp;
        depositorDetails[msg.sender].withdrawed = true;

        emit Withdraw(msg.sender,_amount);
    }

    function depositToAave() external onlyOwner{
        uint256 share = (address(this).balance)/4;
        require(share > 0,"Null deposit");
        wethGateway.depositETH{value: share}(ethAddress,address(this),0);

        toOutside[1].depositedTime = block.timestamp;
        toOutside[1].hasDeposited = true;
        toOutside[1].depositedAmount += msg.value;
        //toOutside[1].depositedCount += 1;
        uint256 depositedAmount = toOutside[1].depositedAmount;
        toOutside[1].ethPriceAtDeposit = borrowing.getUSDValue();
        toOutside[1].depositedUsdValue = depositedAmount * depositorDetails[1].ethPriceAtDeposit;

    }

}