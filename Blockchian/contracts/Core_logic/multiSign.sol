// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract MultiSign {

    address[] public owners; // Owners array
    mapping(address => bool) public isOwner; // To check the address is owner
    uint64 public requiredApprovals; // Required number of approvals to execute the function
    mapping(address => bool) public approved; // Check which owners were approved

    constructor(address[] memory _owners,uint64 _requiredApprovals){
        require(_owners.length > 0,'Owners required');
        require(_requiredApprovals > 0 && _requiredApprovals <= _owners.length,'Invalid number of required approvals');

        for(uint64 i; i < _owners.length;i++){
            address owner = _owners[i];

            require(owner != address(0),'Invalid owner');
            require(!isOwner[owner],'Duplicate owner');

            isOwner[owner] = true;
            owners.push(owner);
        }

        requiredApprovals = _requiredApprovals;
    }

    modifier onlyOwners(){
        require(isOwner[msg.sender],'Not an owner');
        _;
    }

    // Owners can approve the execution
    function approve() public onlyOwners{
        require(!approved[msg.sender],'Already approved');
        approved[msg.sender] = true;
    }

    // To get number of approvals till now
    function getApprovalCount() private view returns (uint64){
        uint64 count;
        for(uint64 i; i < owners.length;i++){
            if(approved[owners[i]]){
                count += 1;
            }
        }
        return count;
    }

    // If the required number of approvals are met,then return true
    function execute() public returns (bool){
        require(getApprovalCount() >= requiredApprovals,'Required approvals not met');
        for(uint64 i; i < owners.length;i++){
            approved[owners[i]] = false;
        }
        return true;
    }
}