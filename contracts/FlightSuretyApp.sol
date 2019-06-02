pragma solidity ^0.5.0;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
  using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)

  /********************************************************************************************/
  /*                                       DATA VARIABLES                                     */
  /********************************************************************************************/

  // FlightSurety data contract
  FlightSuretyData flightSuretyData;

  // Account used to deploy contract
  address private contractOwner;

  // Multi-party consensus for airline registration
  mapping(address => address[]) private registerAirlineMultiCalls;

  // Registration of fifth and subsequent airlines requires multi-party consensus of 50% of registered airlines
  uint constant REGISTER_AIRLINE_MULTI_CALL_THRESHOLD = 4;
  uint constant REGISTER_AIRLINE_MULTI_CALL_CONSENSUS_DIVISOR = 2;

  // Airline Ante: Airline can be registered, but does not participate in contract until it submits funding of 10 ether
  uint constant AIRLINE_FUNDING_VALUE = 10 ether;

  // Passenger Payment: Passengers may pay up to 1 ether for purchasing flight insurance
  uint constant MAX_PASSENGER_INSURANCE_VALUE = 1 ether;

  // Insurance multiplier in percentage
  uint constant INSURANCE_MULTIPLIER = 150; // 150%

  /********************************************************************************************/
  /*                                       CONSTRUCTOR                                        */
  /********************************************************************************************/

  /**
  * @dev Contract constructor
  *
  */
  constructor(address dataContract) public {
    contractOwner = msg.sender;
    flightSuretyData = FlightSuretyData(dataContract);
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
    // Modify to call data contract's status
    require(flightSuretyData.isOperational(), "Contract is currently not operational");  
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
   * @dev Modifier that requires airline to be funded
   */
  modifier requireAirlineIsFunded(address airline) {
    require(flightSuretyData.isFundedAirline(airline), "Only existing and funded airlines are allowed");
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

  event AirlineRegistered(string name, address addr, bool success, uint256 votes);
  event AirlineFunded(address addr, uint amount);
  event FlightRegistered(address airline, string flight, string from, string to, uint256 timestamp);
  event InsuranceBought(address airline, string flight, uint256 timestamp, address passenger, uint256 amount, uint256 multiplier);

  /********************************************************************************************/
  /*                                       UTILITY FUNCTIONS                                  */
  /********************************************************************************************/

  function isOperational() external view returns(bool) {
    return flightSuretyData.isOperational();
  }

  /********************************************************************************************/
  /*                                     SMART CONTRACT FUNCTIONS                             */
  /********************************************************************************************/

  /**
   * @dev Add an airline to the registration queue
   * 
   * Multiparty Consensus: Only existing airline may register a new airline until there are at least four airlines registered
   * Airline Ante: Airline can be registered, but does not participate in contract until it submits funding of 10 ether
   */
  function registerAirline(string memory name, address addr) public requireIsOperational requireValidAddress(addr) requireAirlineIsFunded(msg.sender) returns(bool success, uint256 votes) {
    bool result = false;
    address[] memory registeredAirlines = flightSuretyData.getRegisteredAirlines();

    // Register first airline
    if(registeredAirlines.length == 0) {
      result = flightSuretyData.registerAirline(name, addr);
    }
    else if(registeredAirlines.length < REGISTER_AIRLINE_MULTI_CALL_THRESHOLD) {
      result = flightSuretyData.registerAirline(name, addr);
    }
    // Multiparty Consensus: Registration of fifth and subsequent airlines requires multi-party consensus of 50% of registered airlines
    else {
      bool isDuplicate = false;

      for(uint i = 0; i < registerAirlineMultiCalls[addr].length; i++) {
        if (registerAirlineMultiCalls[addr][i] == msg.sender) {
          isDuplicate = true;
          break;
        }
      }

      require(!isDuplicate, "Caller has already called this function.");

      registerAirlineMultiCalls[addr].push(msg.sender);

      if (registerAirlineMultiCalls[addr].length >= registeredAirlines.length.div(REGISTER_AIRLINE_MULTI_CALL_CONSENSUS_DIVISOR)) {
        result = flightSuretyData.registerAirline(name, addr);
        registerAirlineMultiCalls[addr] = new address[](0);
      }
    }

    emit AirlineRegistered(name, addr, result, registerAirlineMultiCalls[addr].length);
    return (result, registerAirlineMultiCalls[addr].length);
  }

  /**
   * @dev Submit funding for airline
   */   
  function fundAirline() payable external requireIsOperational {
    require(msg.value == AIRLINE_FUNDING_VALUE, "Not correct funding value submitted");

    // Cast address to payable address
    address(uint160(address(flightSuretyData))).transfer(msg.value);
    
    flightSuretyData.fundAirline(msg.sender);

    emit AirlineFunded(msg.sender, msg.value);
  }

  /**
   * @dev Register a future flight for insuring.
   */  
  function registerFlight(string calldata flight, string calldata from, string calldata to, uint256 timestamp) external requireIsOperational requireValidAddress(msg.sender) requireAirlineIsFunded(msg.sender) {
    flightSuretyData.registerFlight(msg.sender, flight, from, to, timestamp);
    emit FlightRegistered(msg.sender, flight, from, to, timestamp);
  }

  /**
   * @dev Buy insurance for a flight
   */   
  function buyInsurance(address airline, string calldata flight, uint256 timestamp) external payable requireIsOperational {
    require(msg.value > 0 && msg.value <= MAX_PASSENGER_INSURANCE_VALUE, "Insurance value is not within the limits");
    require(flightSuretyData.isFlight(airline, flight, timestamp), "Flight is not registered");
    require(!flightSuretyData.isLandedFlight(airline, flight, timestamp), "Flight already landed");
    require(!flightSuretyData.isInsured(msg.sender, airline, flight, timestamp), "Passenger already bought insurance for this flight");
  
    // Cast address to payable address
    address(uint160(address(flightSuretyData))).transfer(msg.value);
    
    flightSuretyData.buy(airline, flight, timestamp, msg.sender, msg.value, INSURANCE_MULTIPLIER);

    emit InsuranceBought(airline, flight, timestamp, msg.sender, msg.value, INSURANCE_MULTIPLIER);
  }

  /**
   * @dev Called after oracle has updated flight status
   */  
  function processFlightStatus(address airline, string memory flight, uint256 timestamp, uint8 statusCode) internal requireIsOperational {
    flightSuretyData.processFlightStatus(airline, flight, timestamp, statusCode);
  }

  // Generate a request for oracles to fetch flight information
  function fetchFlightStatus(address airline, string calldata flight, uint256 timestamp) external {
    uint8 index = getRandomIndex(msg.sender);

    // Generate a unique key for storing the request
    bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
    oracleResponses[key] = ResponseInfo({requester: msg.sender, isOpen: true});

    emit OracleRequest(index, airline, flight, timestamp);
  }

  /**
   * @dev Transfers eligible payout funds to insuree
   */
  function pay() public requireIsOperational {
    flightSuretyData.pay(msg.sender);
  }

  /********************************************************************************************/
  /*                                     ORACLE MANAGEMENT                                    */
  /********************************************************************************************/

  // Incremented to add pseudo-randomness at various points
  uint8 private nonce = 0;    

  // Fee to be paid when registering oracle
  uint256 public constant REGISTRATION_FEE = 1 ether;

  // Number of oracles that must respond for valid status
  uint256 private constant MIN_RESPONSES = 3;

  struct Oracle {
    bool isRegistered;
    uint8[3] indexes;        
  }

  // Track all registered oracles
  mapping(address => Oracle) private oracles;

  // Model for responses from oracles
  struct ResponseInfo {
    address requester;                              // Account that requested status
    bool isOpen;                                    // If open, oracle responses are accepted
    mapping(uint8 => address[]) responses;          // Mapping key is the status code reported
                                                    // This lets us group responses and identify
                                                    // the response that majority of the oracles
  }

  // Track all oracle responses
  // Key = hash(index, flight, timestamp)
  mapping(bytes32 => ResponseInfo) private oracleResponses;

  // Event fired each time an oracle submits a response
  event FlightStatusInfo(address airline, string flight, uint256 timestamp, uint8 status);

  event OracleReport(address airline, string flight, uint256 timestamp, uint8 status);

  // Event fired when flight status request is submitted
  // Oracles track this and if they have a matching index
  // they fetch data and submit a response
  event OracleRequest(uint8 index, address airline, string flight, uint256 timestamp);

  // Register an oracle with the contract
  function registerOracle() external payable requireIsOperational {
    // Require registration fee
    require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

    uint8[3] memory indexes = generateIndexes(msg.sender);

    oracles[msg.sender] = Oracle({isRegistered: true, indexes: indexes});
  }

  function getMyIndexes() view external requireIsOperational returns(uint8[3] memory) {
    require(oracles[msg.sender].isRegistered, "Not registered as an oracle");
    return oracles[msg.sender].indexes;
  }

  // Called by oracle when a response is available to an outstanding request
  // For the response to be accepted, there must be a pending request that is open
  // and matches one of the three Indexes randomly assigned to the oracle at the
  // time of registration (i.e. uninvited oracles are not welcome)
  function submitOracleResponse(uint8 index, address airline, string calldata flight, uint256 timestamp, uint8 statusCode) external requireIsOperational {
    require((oracles[msg.sender].indexes[0] == index) || (oracles[msg.sender].indexes[1] == index) || (oracles[msg.sender].indexes[2] == index), "Index does not match oracle request");

    bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp)); 
    require(oracleResponses[key].isOpen, "Flight or timestamp do not match oracle request");

    oracleResponses[key].responses[statusCode].push(msg.sender);

    // Information isn't considered verified until at least MIN_RESPONSES
    // oracles respond with the *** same *** information
    emit OracleReport(airline, flight, timestamp, statusCode);
    if (oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES) {
      emit FlightStatusInfo(airline, flight, timestamp, statusCode);

      // Handle flight status as appropriate
      processFlightStatus(airline, flight, timestamp, statusCode);
    }
  }

  function getFlightKey(address airline, string memory flight, uint256 timestamp) pure internal returns(bytes32) {
    return keccak256(abi.encodePacked(airline, flight, timestamp));
  }

  // Returns array of three non-duplicating integers from 0-9
  function generateIndexes(address account) internal returns(uint8[3] memory) {
    uint8[3] memory indexes;
    indexes[0] = getRandomIndex(account);
    
    indexes[1] = indexes[0];
    while(indexes[1] == indexes[0]) {
      indexes[1] = getRandomIndex(account);
    }

    indexes[2] = indexes[1];
    while((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
      indexes[2] = getRandomIndex(account);
    }

    return indexes;
  }

  // Returns array of three non-duplicating integers from 0-9
  function getRandomIndex(address account) internal returns (uint8) {
    uint8 maxValue = 10;

    // Pseudo random number...the incrementing nonce adds variation
    uint8 random = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - nonce++), account))) % maxValue);

    if (nonce > 250) {
      nonce = 0;  // Can only fetch blockhashes for last 256 blocks so we adapt
    }

    return random;
  }
}

// FlightSurety data contract interface
contract FlightSuretyData {
  // Utility functions
  function isOperational() public view returns(bool);
  function setOperatingStatus(bool mode) external;

  // Airlines
  function registerAirline(string calldata name, address addr) external returns(bool);
  function isAirline(address airline) external view returns(bool);
  function isFundedAirline(address airline) external view returns(bool);
  function getRegisteredAirlines() external view returns(address[] memory);
  function fundAirline(address addr) payable external;

  // Flights
  function registerFlight(address airline, string calldata flight, string calldata from, string calldata to, uint256 timestamp) external;
  function isFlight(address airline, string calldata flight, uint256 timestamp) external view returns(bool);
  function isLandedFlight(address airline, string calldata flight, uint256 timestamp) external view returns(bool);
  function processFlightStatus(address airline, string calldata flight, uint256 timestamp, uint8 statusCode) external;
  function getFlightStatusCode(address airline, string calldata flight, uint256 timestamp) external view returns(uint8);

  // Passengers
  function buy(address airline, string calldata flight, uint256 timestamp, address passenger, uint256 amount, uint256 multiplier) external payable;
  function isInsured(address passenger, address airline, string calldata flight, uint256 timestamp) external view returns (bool);
  function pay(address passenger) external;
}