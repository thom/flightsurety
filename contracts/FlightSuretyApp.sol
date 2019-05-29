pragma solidity ^0.5.0;

/*
Passengers
[TODO] Passenger Airline Choice: Passengers can choose from a fixed list of flight numbers and departure that are defined in the Dapp client
[TODO] Passenger Payment: Passengers may pay up to 1 ether for purchasing flight insurance.
[TODO] Passenger Repayment: If flight is delayed due to airline fault, passenger receives credit of 1.5X the amount they paid
[TODO] Passenger Withdraw: Passenger can withdraw any funds owed to them as a result of receiving credit for insurance payout
[TODO] Insurance Payouts: Insurance payouts are not sent directly to passenger’s wallet

Oracles (Server App)
[TODO] Functioning Oracle: Oracle functionality is implemented in the server app.
[TODO] Oracle Initialization: Upon startup, 20+ oracles are registered and their assigned indexes are persisted in memory
[TODO] Oracle Updates: Update flight status requests from client Dapp result in OracleRequest event emitted by Smart Contract that is captured by server (displays on [ole and handled in code)
[TODO] Oracle Functionality: Server will loop through all registered oracles, identify those oracles for which the OracleRequest event applies, and respond by calling into FlightSuretyApp contract with random status code of Unknown (0), On Time (10) or Late Airline (20), Late Weather (30), Late Technical (40), or Late Other (50)
*/

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

  // Flight status codes
  uint8 private constant STATUS_CODE_UNKNOWN = 0;
  uint8 private constant STATUS_CODE_ON_TIME = 10;
  uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
  uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
  uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
  uint8 private constant STATUS_CODE_LATE_OTHER = 50;

  address private contractOwner;          // Account used to deploy contract

  // Flights
  struct Flight {
    bool isRegistered;
    uint8 statusCode;
    uint256 updatedTimestamp;        
    address airline;
  }
  mapping(bytes32 => Flight) private flights;

  // Multi-party consensus for airline registration
  mapping(address => address[]) private registerAirlineMultiCalls;

  // Registration of fifth and subsequent airlines requires multi-party consensus of 50% of registered airlines
  uint constant REGISTER_AIRLINE_MULTI_CALL_THRESHOLD = 4;
  uint constant REGISTER_AIRLINE_MULTI_CALL_CONSENSUS_DIVISOR = 2;

  // Airline Ante: Airline can be registered, but does not participate in contract until it submits funding of 10 ether
  uint constant AIRLINE_FUNDING_VALUE = 10 ether;

  /********************************************************************************************/
  /*                                       CONSTRUCTOR                                        */
  /********************************************************************************************/

  /**
  * @dev Contract constructor
  *
  */
  constructor(address dataContract) public {
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
  modifier requireContractOwner()
  {
    require(msg.sender == contractOwner, "Caller is not contract owner");
    _;
  }

  /********************************************************************************************/
  /*                                       EVENT DEFINITIONS                                  */
  /********************************************************************************************/

  event AirlineRegistered(string name, address addr, bool success, uint256 votes);

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
   */
  function registerAirline(string memory name, address addr) public requireIsOperational returns(bool success, uint256 votes) {
    require(addr != address(0), "Invalid address");

    // Multiparty Consensus: Only existing airline may register a new airline until there are at least four airlines registered
    // Airline Ante: Airline can be registered, but does not participate in contract until it submits funding of 10 ether
    require(flightSuretyData.isFundedAirline(msg.sender), "Only existing and funded airlines may register a new airline");

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
    require(msg.value >= AIRLINE_FUNDING_VALUE, "Not enough funding submitted");
    address(uint160(address(flightSuretyData))).transfer(msg.value);
    flightSuretyData.fundAirline(msg.sender);
  }

  /**
   * @dev Register a future flight for insuring.
   */  
  function registerFlight() external requireIsOperational {

  }
  
  /**
   * @dev Called after oracle has updated flight status
   */  
  function processFlightStatus(address airline, string memory flight, uint256 timestamp, uint8 statusCode) internal requireIsOperational {

  }

  // Generate a request for oracles to fetch flight information
  function fetchFlightStatus(address airline, string calldata flight, uint256 timestamp) external {
    uint8 index = getRandomIndex(msg.sender);

    // Generate a unique key for storing the request
    bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
    oracleResponses[key] = ResponseInfo({requester: msg.sender, isOpen: true});

    emit OracleRequest(index, airline, flight, timestamp);
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
  function isOperational() public view returns(bool);
  function setOperatingStatus(bool mode) external;

  // Airlines
  function registerAirline(string calldata name, address addr) external returns(bool);
  function isAirline(address airline) external view returns(bool);
  function isFundedAirline(address airline) external view returns(bool);
  function getRegisteredAirlines() external view returns(address[] memory);
  function fundAirline(address addr) payable external;
}