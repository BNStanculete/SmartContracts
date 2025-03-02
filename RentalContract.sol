// Copyright 2025 Bogdan Stanculete. All Rights Reserved.
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract RentalAgreement is ReentrancyGuard {
    // The tenant is the person who is currently renting the appartment
    address payable public _tenant;

    // The owner of the contract is the one who owns the property
    address payable public _owner;

    // The monthly rent (in WEI) to be paid
    uint256 public _monthlyRent;

    // The deposit (in WEI) which has to be paid by the tenant
    uint256 public _deposit;

    // Extra charges to be paid with the next monthly rent.
    uint256 public _extraCharges;

    // Timestamps for when the agreement becomes active and when it expires
    uint256 public _startTimestamp;
    uint256 public _expirationTimestamp;
    uint256 public _intialAgreementPeriod;

    // The status of paying the monthly rent
    enum RentStatus {
        PAID,
        UNPAID,
        OVERDUE,
        INACTIVE
    }
    RentStatus public _status;

    // Variables for the contract to know how much to refund / send to the owner
    // in the event of a payment failure.
    uint256 private _uncollectedRent;
    uint256 private _uncollectedChange;

    // --- Modifiers for enforcing access control ---

    modifier onlyOwner() {
        require(_owner == msg.sender, "Access denied for non-owners.");
        _;
    }

    modifier onlyTenant() {
        require(msg.sender == _tenant, "Access denied for non-tenants.");
        _;
    }

    modifier validContract() {
        require(block.timestamp >= _startTimestamp && block.timestamp <= _expirationTimestamp, "RentalContract is not yet active or is expired.");
        require(_tenant != address(0), "There is no tenant registered for this contract.");
        _;
    }

    modifier inactiveContract() {
        require(_tenant == address(0), "The contract already has a tenant and a rental period.");
        _;
    }

    // --- Events for notification purposes ---

    event ExtraCharges(uint256 value);
    event MonthlyRent(uint256 value);
    event PaymentFailed(address destination, uint256 value);
    event UnexpectedTransfer(address sender, uint256 amount);

    // --- Contract ctor and views ---

    constructor(address payable owner,
                uint256 monthlyRent,
                uint256 requiredDeposit,
                uint256 initialAgreementPeriod) {
        _tenant = payable(address(0));
        _owner = owner;

        _startTimestamp = 0;
        _expirationTimestamp = 0;
        _intialAgreementPeriod = initialAgreementPeriod;

        _deposit = requiredDeposit;
        _monthlyRent = monthlyRent;
        _extraCharges = 0;

        _uncollectedChange = 0;
        _uncollectedRent = 0;

        _status = RentStatus.INACTIVE;
    }

    function getOwner() public view returns (address) { return _owner; }
    function getTenant() public view returns (address) { return _tenant; }

    function getRequiredDeposit() public view returns (uint256) { return _deposit; }
    function getMonthlyRent() public view returns (uint256) { return _monthlyRent; }
    function getExtraCharges() public view returns (uint256) { return _extraCharges; }

    function getRentStatus() public view returns (RentStatus) { return _status; }

    function getActivationTimestamp() public view returns (uint256) { return _startTimestamp; }
    function getExpirationTimestamp() public view returns (uint256) { return _expirationTimestamp; }
    function getTimeUntilExpiration() public view validContract returns (uint256) { 
        return _expirationTimestamp - block.timestamp; 
    }

    // --- Contract methods ---

    function registerTenant(address payable tenant) onlyTenant inactiveContract public payable nonReentrant {
        require(tenant != address(0), "Invalid tenant address.");
        require(msg.value >= _deposit, "Insufficient funds to pay the required deposit.");

        _tenant = tenant;
        _status = RentStatus.PAID;
        _startTimestamp = block.timestamp;
        _expirationTimestamp = _startTimestamp + _intialAgreementPeriod;

        (bool success, ) = _owner.call{ value: _deposit }("");
        if (!success) { _uncollectedChange += _deposit; emit PaymentFailed(_owner, _deposit); }
    }

    function payRent() onlyTenant validContract public payable nonReentrant {
        require(_status == RentStatus.UNPAID, "The rent for this month has already been paid");
        require(msg.value >= _monthlyRent + _extraCharges, "Insufficient funds to pay the monthly rent.");

        uint256 extraPayment = msg.value - _monthlyRent - _extraCharges;
        uint256 rent = msg.value - extraPayment;
        
        _status = RentStatus.PAID;
        _extraCharges = 0;

        (bool successOwner, ) = _owner.call{ value: rent }("");
        if (!successOwner) {
            _uncollectedRent += rent;

            emit PaymentFailed(_owner, rent);
        }

        // If the tenant paid more than needed, the rest is returned back.
        if (extraPayment > 0) {
            (bool successTenant, ) = _tenant.call{ value: extraPayment}("");
            if (!successTenant) {
                _uncollectedChange += extraPayment;

                emit PaymentFailed(_tenant, extraPayment);
            }
        }
    }

    function setMonthlyCharges(uint256 extraCharges) onlyOwner validContract public {
        _status = RentStatus.UNPAID;
        _extraCharges = extraCharges;

        if (extraCharges > 0)
            emit ExtraCharges(_extraCharges);
        emit MonthlyRent(_monthlyRent + _extraCharges);
    }

    function extendRentalPeriod(uint256 extendedTime) onlyOwner validContract public {
        require(extendedTime > 0 && extendedTime <= 365 days, "Invalid extended time period");
        
        _expirationTimestamp += extendedTime;
    }

    function terminateRental() onlyOwner validContract public payable nonReentrant {
        uint256 amountToRefund = _deposit + _uncollectedChange;
        if (_status == RentStatus.UNPAID) { amountToRefund -= _monthlyRent - _extraCharges; }

        require(amountToRefund > 0, "Cannot terminate contract due to unpaid charges.");
        require(msg.value == amountToRefund, string(abi.encodePacked("Must pay back tenant deposit: ", Strings.toString(amountToRefund))));

        _status = RentStatus.INACTIVE;
        _expirationTimestamp = 0;
        _startTimestamp = 0;

        (bool success, ) = _tenant.call{ value: amountToRefund }("");
        if (!success) { emit PaymentFailed(_tenant, amountToRefund); }

        _uncollectedChange = 0;
        _tenant = payable(address(0));
    }

    // --- Recovery functions ---

    function collectRent() onlyOwner public nonReentrant {
        require(_uncollectedRent > 0, "There is no uncollected rent.");

        (bool success, ) = _owner.call{ value: _uncollectedRent }("");

        if (!success) { emit PaymentFailed(_owner, _uncollectedRent); }
        else { _uncollectedRent = 0; }
    }

    function collectChange() onlyTenant public nonReentrant {
        require(_uncollectedChange > 0, "There is no uncollected change.");

        (bool success, ) = _tenant.call{ value: _uncollectedChange }("");

        if (!success) { emit PaymentFailed(_owner, _uncollectedChange); }
        else { _uncollectedChange = 0; }
    }

    // --- Fallback functions ---

    receive() external payable { 
        emit UnexpectedTransfer(msg.sender, msg.value);
        revert("The contract cannot be paid directly.");
    }
}