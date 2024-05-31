// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract MultiSignV1 {

    address[] internal owners; // Owners array
    uint8 internal maxOwners;
    uint8 internal noOfOwners;
    mapping(address => bool) public isOwner; // To check the address is owner
    uint64 internal requiredApprovals; // Required number of approvals to execute the function
    enum SetterFunctions{
        SetLTV,
        SetAPR,
        SetWithdrawTimeLimitCDS,
        SetAdminBorrow,
        SetAdminCDS,
        SetTreasuryBorrow,
        SetTreasuryCDS,
        SetBondRatio,
        SetUSDaLimit,
        SetUsdtLimit
    }
    enum Functions{
        BorrowingDeposit,
        BorrowingWithdraw,
        Liquidation,
        SetAPR,
        CDSDeposit,
        CDSWithdraw,
        RedeemUSDT
    }

    mapping(SetterFunctions => mapping(address owner => bool approved)) public approvedToUpdate; // Check which owners were approved

    mapping (Functions => mapping(address owner => bool paused)) pauseApproved; // Store what functions are approved for pause by owners
    mapping (Functions => mapping(address owner => bool unpaused)) unpauseApproved; // Store what functions are approved for unpause by owners

    mapping (Functions => bool paused) public functionState; // Returns true if function is in pause state

}