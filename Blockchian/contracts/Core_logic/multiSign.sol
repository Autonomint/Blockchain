// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { MultiSignV1 } from "../v1Contracts/multiSignV1.sol";

contract MultiSign is MultiSignV1, Initializable,OwnableUpgradeable,UUPSUpgradeable {

    function initialize(
        address[] memory _owners,
        uint64 _requiredApprovals
    ) initializer public{
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        uint8 _noOfOwners = uint8(_owners.length);
        require(_noOfOwners > 0,'Owners required');
        maxOwners = 10;
        require (_noOfOwners <= maxOwners,"Number of owners should be below maximum owners limit");
        require(_requiredApprovals > 0 && _requiredApprovals <= _noOfOwners,'Invalid number of required approvals');

        for(uint64 i; i < _noOfOwners;i++){
            address owner = _owners[i];

            require(owner != address(0),'Invalid owner');
            require(!isOwner[owner],'Duplicate owner');

            isOwner[owner] = true;
            owners.push(owner);
        }

        requiredApprovals = _requiredApprovals;
        noOfOwners = _noOfOwners;
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override{}

    modifier onlyOwners(){
        require(isOwner[msg.sender],'Not an owner');
        _;
    }

    // Function to approve pause takes enum for which function to pause
    function approvePause(uint8[] memory functions) external onlyOwners{
        uint8 noOfFunctions = uint8(functions.length);
        require(noOfFunctions > 0,"Empty array");
        for(uint8 i = 0;i < noOfFunctions;i++){
            require(!pauseApproved[Functions(functions[i])][msg.sender],'Already approved');
            pauseApproved[Functions(functions[i])][msg.sender] = true;
        }
    }

    // Function to approve set apr
    function approveSetterFunction(uint8[] memory functions) external onlyOwners{
        uint8 noOfFunctions = uint8(functions.length); 
        require(noOfFunctions > 0,"Empty array");
        for(uint8 i = 0;i < noOfFunctions;i++){
            require(!approvedToUpdate[SetterFunctions(functions[i])][msg.sender],'Already approved');
            approvedToUpdate[SetterFunctions(functions[i])][msg.sender] = true;
        }
    }

    // Function to approve unpause takes enum for which function to pause
    function approveUnPause(uint8[] memory functions) external onlyOwners{
        uint8 noOfFunctions = uint8(functions.length);
        require(noOfFunctions > 0,"Empty array");
        for(uint8 i = 0;i < noOfFunctions;i++){
            require(!unpauseApproved[Functions(functions[i])][msg.sender],'Already approved');
            unpauseApproved[Functions(functions[i])][msg.sender] = true;
        }

    }

    // Function to approve pause the borrowing contract
    function approveBorrowingPause() external onlyOwners{
        require(!pauseApproved[Functions.BorrowingDeposit][msg.sender],'BorrowingDeposit Already approved');
        require(!pauseApproved[Functions.BorrowingWithdraw][msg.sender],'BorrowingWithdraw Already approved');
        require(!pauseApproved[Functions.Liquidation][msg.sender],'Liquidation Already approved');
        require(!pauseApproved[Functions.SetAPR][msg.sender],'SetAPR Already approved');

        pauseApproved[Functions.BorrowingDeposit][msg.sender] = true;
        pauseApproved[Functions.BorrowingWithdraw][msg.sender] = true;
        pauseApproved[Functions.Liquidation][msg.sender] = true;
        pauseApproved[Functions.SetAPR][msg.sender] = true;
    }

    // Function to approve pause the CDS contract
    function approveCDSPause() external onlyOwners{
        require(!pauseApproved[Functions.CDSDeposit][msg.sender],'CDSDeposit Already approved');
        require(!pauseApproved[Functions.CDSWithdraw][msg.sender],'CDSWithdraw Already approved');
        require(!pauseApproved[Functions.RedeemUSDT][msg.sender],'RedeemUSDT Already approved');

        pauseApproved[Functions.CDSDeposit][msg.sender] = true;
        pauseApproved[Functions.CDSWithdraw][msg.sender] = true;
        pauseApproved[Functions.RedeemUSDT][msg.sender] = true;
    }

    // Function to approve unpause the borrowing contract
    function approveBorrowingUnPause() external onlyOwners{
        require(!unpauseApproved[Functions.BorrowingDeposit][msg.sender],'BorrowingDeposit Already approved');
        require(!unpauseApproved[Functions.BorrowingWithdraw][msg.sender],'BorrowingWithdraw Already approved');
        require(!unpauseApproved[Functions.Liquidation][msg.sender],'Liquidation Already approved');
        require(!unpauseApproved[Functions.SetAPR][msg.sender],'SetAPR Already approved');

        unpauseApproved[Functions.BorrowingDeposit][msg.sender] = true;
        unpauseApproved[Functions.BorrowingWithdraw][msg.sender] = true;
        unpauseApproved[Functions.Liquidation][msg.sender] = true;
        unpauseApproved[Functions.SetAPR][msg.sender] = true;
    }

    // Function to approve unpause the CDS contract
    function approveCDSUnPause() external onlyOwners{
        require(!unpauseApproved[Functions.CDSDeposit][msg.sender],'CDSDeposit Already approved');
        require(!unpauseApproved[Functions.CDSWithdraw][msg.sender],'CDSWithdraw Already approved');
        require(!unpauseApproved[Functions.RedeemUSDT][msg.sender],'RedeemUSDT Already approved');

        unpauseApproved[Functions.CDSDeposit][msg.sender] = true;
        unpauseApproved[Functions.CDSWithdraw][msg.sender] = true;
        unpauseApproved[Functions.RedeemUSDT][msg.sender] = true;
    }

    // Gets the pause approval count
    function getApprovalPauseCount(Functions _function) private view returns (uint64){
        uint64 count;
        for(uint64 i; i < noOfOwners;i++){
            if(pauseApproved[_function][owners[i]]){
                count += 1;
            }
        }
        return count;
    }

    // Gets the unpause approval count
    function getApprovalUnPauseCount(Functions _function) private view returns (uint64){
        uint64 count;
        for(uint64 i; i < noOfOwners;i++){
            if(unpauseApproved[_function][owners[i]]){
                count += 1;
            }
        }
        return count;
    }

    // Gets the set APR approval count
    function getSetterFunctionApproval(SetterFunctions _function) private view returns (uint64){
        uint64 count;
        for(uint64 i; i < noOfOwners;i++){
            if(approvedToUpdate[_function][owners[i]]){
                count += 1;
            }
        }
        return count;
    }

    // Returns true if the function is eligible to pause
    function executePause(Functions _function) private returns (bool){
        require(getApprovalPauseCount(_function) >= requiredApprovals,'Required approvals not met');
        for(uint64 i; i < noOfOwners;i++){
            pauseApproved[_function][owners[i]] = false;
        }
        return true;
    }

    // Returns true if the function is eligible to unpause
    function executeUnPause(Functions _function) private returns (bool){
        require(getApprovalUnPauseCount(_function) >= requiredApprovals,'Required approvals not met');
        for(uint64 i; i < noOfOwners;i++){
            unpauseApproved[_function][owners[i]] = false;
        }
        return true;
    }

    // Returns true if eligible to set APR
    function executeSetterFunction(SetterFunctions _function) external returns (bool){
        require(getSetterFunctionApproval(_function) >= requiredApprovals,'Required approvals not met');
        for(uint64 i; i < noOfOwners;i++){
            approvedToUpdate[_function][owners[i]] = false;
        }
        return true;
    }

    // Pause the given function
    function pauseFunction(uint8[] memory functions) external onlyOwners{
        uint8 noOfFunctions = uint8(functions.length);
        require(noOfFunctions > 0,"Empty array");
        for(uint8 i = 0;i < noOfFunctions;i++){
            require(executePause(Functions(functions[i])));
            functionState[Functions(functions[i])] = true;
        }

    }

    // Unpause the given function
    function unpauseFunction(uint8[] memory functions) external onlyOwners{
        uint8 noOfFunctions = uint8(functions.length);
        require(noOfFunctions > 0,"Empty array");
        for(uint8 i = 0;i < noOfFunctions;i++){
            require(executeUnPause(Functions(functions[i])));
            functionState[Functions(functions[i])] = false;
        }

    }

    // Pause Borrowing
    function pauseBorrowing() external onlyOwners{
        require(executePause(Functions(0)) && executePause(Functions(1)) && executePause(Functions(2)) && executePause(Functions(3)));
        functionState[Functions.BorrowingDeposit] = true;
        functionState[Functions.BorrowingWithdraw] = true;
        functionState[Functions.Liquidation] = true;
        functionState[Functions.SetAPR] = true;
    }

    // Pause CDS
    function pauseCDS() external onlyOwners{
        require(executePause(Functions(4)) && executePause(Functions(5)) && executePause(Functions(6)));
        functionState[Functions.CDSDeposit] = true;
        functionState[Functions.CDSWithdraw] = true;
        functionState[Functions.RedeemUSDT] = true;
    }

    // Unpause Borrowing
    function unpauseBorrowing() external onlyOwners{
        require(executeUnPause(Functions(0)) && executeUnPause(Functions(1)) && executeUnPause(Functions(2)) && executeUnPause(Functions(3)));
        functionState[Functions.BorrowingDeposit] = false;
        functionState[Functions.BorrowingWithdraw] = false;
        functionState[Functions.Liquidation] = false;
        functionState[Functions.SetAPR] = false;
    }

    // Unpause CDS
    function unpauseCDS() external onlyOwners{
        require(executeUnPause(Functions(4)) && executeUnPause(Functions(5)) && executeUnPause(Functions(6)));
        functionState[Functions.CDSDeposit] = false;
        functionState[Functions.CDSWithdraw] = false;
        functionState[Functions.RedeemUSDT] = false;
    }
}