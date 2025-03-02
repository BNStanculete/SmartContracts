// Copyright 2025 Bogdan Stanculete. All Rights Reserved.
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RentalToken is ERC20 {
    // Total supply can be controlled by the owner (landlord or a centralized authority)
    address public owner;

    // Modifier to restrict functions to the contract owner
    modifier onlyOwner() {
        require(msg.sender == owner, "You are not the owner");
        _;
    }

    constructor() ERC20("Rental Payment Token", "RPT") {
        owner = msg.sender;
    }

    // Mint new tokens to a specific address
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    // Burn tokens from an address
    function burn(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
    }

    // Function to transfer ownership to a new address (only the current owner can call this)
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner address cannot be the zero address");
        owner = newOwner;
    }
}