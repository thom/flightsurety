pragma solidity ^0.5.0;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
  using SafeMath for uint256;

  /********************************************************************************************/
  /*                                       DATA VARIABLES                                     */
  /********************************************************************************************/

  address private contractOwner;                                      // Account used to deploy contract
  bool private operational = true;                                    // Blocks all state changes throughout the contract if false

  // Multi-party consensus
  // Added to setOperational() to practice the concept
  uint constant M = 1;
  address[] multiCalls = new address[](0);

  // Restrict data contract callers
  mapping(address => uint256) private authorizedContracts;

  // Airlines
  struct Airline {
    string name;
    bool isFunded;
    bool isRegistered;
  }
  mapping(address => Airline) private airlines;
  address[] registeredAirlines = new address[](0);

  // Flights
  struct Flight {
    bool isRegistered;
    uint8 statusCode; // 0: unknown (in-flight), >0: landed
    uint256 updatedTimestamp;
    address airline;
    string flight;
    string from;
    string to;
  }
  mapping(bytes32 => Flight) private flights;
  bytes32[] registeredFlights = new bytes32[](0);

  // Insurances
  struct Insurance {
    address passenger;
    uint256 payment; // Passenger insurance payment
    uint256 multiplier; // General damages multiplier (1.5x by default)
    bool isCredited;
  }
  mapping (bytes32 => Insurance[]) insuredPassengersPerFlight;
  mapping (address => uint) public pendingPayments;

  /********************************************************************************************/
  /*                                       CONSTRUCTOR                                        */
  /********************************************************************************************/

  /**
  * @dev Constructor
  *      The deploying account becomes contractOwner
  */
  constructor(string memory firstAirlineName, address firstAirlineAddress) public {
    contractOwner = msg.sender;
  
    // Airline Contract Initialization: First airline is registered when contract is deployed
    airlines[firstAirlineAddress] = Airline({
      name: firstAirlineName,
      isFunded: false, 
      isRegistered: true
    });

    registeredAirlines.push(firstAirlineAddress);
  }

  /********************************************************************************************/
  /*                                       FUNCTION MODIFIERS                                 */
  /********************************************************************************************/

  // Modifiers help avoid duplication of code. They are typically used to validate something
  // before a function is allowed to be executed.

  /**
   * @dev Modifier that requires the "operational" boolean variable to be "true"
   *      This is used on all state changing functions to pause the contract in 
   *      the event there is an issue that needs to be fixed
   */
  modifier requireIsOperational() {
    require(isOperational(), "Contract is currently not operational");
    _;  // All modifiers require an "_" which indicates where the function body will be added
  }

  /**
   * @dev Modifier that requires the "ContractOwner" account to be the function caller
   */
  modifier requireContractOwner() {
    require(msg.sender == contractOwner, "Caller is not contract owner");
    _;
  }

  /**
   * @dev Modifier that requires function caller to be authorized
   */
  modifier requireIsCallerAuthorized() {
    require(authorizedContracts[msg.sender] == 1, "Caller is not authorized");
    _;
  }

  /**
   * @dev Modifier that requires airline to be funded
   */
  modifier requireAirlineIsFunded(address airline) {
    require(this.isFundedAirline(airline), "Only existing and funded airlines are allowed");
    _;
  }

  /**
   * @dev Modifier that requires address to be valid
   */
  modifier requireValidAddress(address addr) {
    require(addr != address(0), "Invalid address");
    _;
  }

  /********************************************************************************************/
  /*                                       EVENT DEFINITIONS                                  */
  /********************************************************************************************/

  event AirlineRegistered(string name, address addr);
  event AirlineFunded(string name, address addr);
  event FlightRegistered(bytes32 flightKey, address airline, string flight, string from, string to, uint256 timestamp);

  /********************************************************************************************/
  /*                                       UTILITY FUNCTIONS                                  */
  /********************************************************************************************/

  /**
   * @dev Get operating status of contract
   *
   * @return A bool that is the current operating status
   */      
  function isOperational() public view returns(bool) {
    return operational;
  }

  /**
   * @dev Get airline details
   *
   * @return Airline with the provided address
   */
  function getAirlineName(address airline) external view returns(string memory) {
    return airlines[airline].name;
  }

  /**
   * @dev Check if the address is a registered airline
   *
   * @return A bool confirming whether or not the address is a registered airline
   */
  function isAirline(address airline) external view returns(bool) {
    return airlines[airline].isRegistered;
  }

  /**
   * @dev Check if the address is a funded airline
   *
   * @return A bool confirming whether or not the address is a funded airline
   */
  function isFundedAirline(address airline) external view returns(bool) {
    return airlines[airline].isFunded;
  }

  /**
   * @dev Get registered airlines
   *
   * @return An array with the addresses of all registered airlines
   */
  function getRegisteredAirlines() external view returns(address[] memory) {
    return registeredAirlines;
  }

  /**
   * @dev Check if the flight is registered
   */
  function isFlight(address airline, string calldata flight, uint256 timestamp) external view returns(bool) {
    bytes32 key = getFlightKey(airline, flight, timestamp);
    return flights[key].isRegistered;
  }

  /**
   * @dev Sets contract operations on/off
   *
   * When operational mode is disabled, all write transactions except for this one will fail
   */    
  function setOperatingStatus(bool mode) external requireContractOwner {
    require(mode != operational, "New mode must be different from existing mode");

    bool isDuplicate = false;

    for(uint i = 0; i < multiCalls.length; i++) {
      if (multiCalls[i] == msg.sender) {
        isDuplicate = true;
        break;
      }
    }

    require(!isDuplicate, "Caller has already called this function.");

    multiCalls.push(msg.sender);

    if (multiCalls.length >= M) {
      operational = mode;
      multiCalls = new address[](0);
    }
  }

  /**
   * @dev Adds address to authorized contracts
   */
  function authorizeCaller(address contractAddress) external requireContractOwner {
    authorizedContracts[contractAddress] = 1;
  }

  /**
   * @dev Removes address from authorized contracts
   */
  function deauthorizeCaller(address contractAddress) external requireContractOwner {
    delete authorizedContracts[contractAddress];
  }

  /********************************************************************************************/
  /*                                     SMART CONTRACT FUNCTIONS                             */
  /********************************************************************************************/

  /**
   * @dev Add an airline to the registration queue
   *      Can only be called from FlightSuretyApp contract
   */
  function registerAirline(string calldata name, address addr) external requireIsOperational requireIsCallerAuthorized requireValidAddress(addr) returns(bool success) {
    require(!airlines[addr].isRegistered, "Airline has already been registered");

    bool result = true;

    airlines[addr] = Airline({
      name: name,
      isFunded: false, 
      isRegistered: true
    });

    registeredAirlines.push(addr);

    emit AirlineRegistered(name, addr);

    return result;
  }

  /**
   * @dev Submit funding for airline
   */   
  function fundAirline(address addr) payable external requireIsOperational requireIsCallerAuthorized {
    airlines[addr].isFunded = true;
    emit AirlineFunded(airlines[addr].name, addr);
  }

  /**
   * @dev Register a flight
   */
  function registerFlight(address airline, string calldata flight, string calldata from, string calldata to, uint256 timestamp) external requireIsOperational requireIsCallerAuthorized requireValidAddress(airline) requireAirlineIsFunded(airline) {
    bytes32 flightKey = getFlightKey(airline, flight, timestamp);
    require(!flights[flightKey].isRegistered, "Flight has already been registered");

    flights[flightKey] = Flight({
      isRegistered: true,
      statusCode: 0,
      updatedTimestamp: timestamp,
      airline: airline,
      flight: flight,
      from: from,
      to: to
    });

    registeredFlights.push(flightKey);

    emit FlightRegistered(flightKey, airline, flight, from, to, timestamp);
  }

  /**
   * @dev Buy insurance for a flight
   */   
  function buy() external payable requireIsOperational {

  }

  /**
   * @dev Credits payouts to insurees
   */
  function creditInsurees() external requireIsOperational requireIsCallerAuthorized {
  }
  

  /**
   * @dev Transfers eligible payout funds to insuree
   */
  function pay() external requireIsOperational requireIsCallerAuthorized {

  }

  /**
   * @dev Initial funding for the insurance. Unless there are too many delayed flights
   *      resulting in insurance payouts, the contract should be self-sustaining
   */   
  function fund() public payable requireIsOperational {

  }

  function getFlightKey(address airline, string memory flight, uint256 timestamp) pure internal returns(bytes32) {
    return keccak256(abi.encodePacked(airline, flight, timestamp));
  }

  /**
   * @dev Fallback function for funding smart contract.
   */
  function() external payable {
    fund();
  }
}