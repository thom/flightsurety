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

  /********************************************************************************************/
  /*                                       CONSTRUCTOR                                        */
  /********************************************************************************************/

  /**
  * @dev Constructor
  *      The deploying account becomes contractOwner
  */
  constructor() public {
      contractOwner = msg.sender;
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

  /********************************************************************************************/
  /*                                       EVENT DEFINITIONS                                  */
  /********************************************************************************************/

  //TBD

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
  *
  */   
  function registerAirline() external requireIsOperational {

  }

  /**
  * @dev Buy insurance for a flight
  *
  */   
  function buy() external payable requireIsOperational {

  }

  /**
    *  @dev Credits payouts to insurees
  */
  function creditInsurees() external requireIsOperational {
  }
  

  /**
    *  @dev Transfers eligible payout funds to insuree
    *
  */
  function pay() external requireIsOperational {

  }

  /**
  * @dev Initial funding for the insurance. Unless there are too many delayed flights
  *      resulting in insurance payouts, the contract should be self-sustaining
  *
  */   
  function fund() public payable requireIsOperational {

  }

  function getFlightKey(address airline, string memory flight, uint256 timestamp) pure internal returns(bytes32) {
    return keccak256(abi.encodePacked(airline, flight, timestamp));
  }

  /**
  * @dev Fallback function for funding smart contract.
  *
  */
  function() external payable {
    fund();
  }
}