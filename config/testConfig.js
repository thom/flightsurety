
var FlightSuretyApp = artifacts.require("FlightSuretyApp");
var FlightSuretyData = artifacts.require("FlightSuretyData");
var BigNumber = require('bignumber.js');

var Config = async function(accounts) {
    
    // These test addresses are useful when you need to add
    // multiple users in test scripts
    let testAddresses = [
        "0xee7bd0d9f39e605cf6f349e4fca8c32b07232ecb",
        "0xbb91f66cbed5876315105050346c42f80e35fd73",
        "0x938cf73ff916cbd4ac23680411e12986ae03b55e",
        "0xbac3a69c715f8fa682680e2f0f3be10f0e0c92e5",
        "0x542d0f3afac66b7483cc5a8db18747a129a84523",
        "0xbad7403acb73e5178e4c3a1b53e55b1b3894e000",
        "0x6c344495cd95a5bb240f3976a44dc748e858e38c",
        "0xc818fdc5f2a71106bb053d26cb554fdec3823537",
        "0xaae25e5b9ffa8aaf1daee102c4235a961d1c8e44",
        "0xb79638b497e108a099ee29976d744f42929fb9b8"
    ];


    let owner = accounts[0];
    let firstAirlineAddress = accounts[1];
    let firstAirlineName = "Swiss International Airlines";

    let flightSuretyData = await FlightSuretyData.new(firstAirlineName, firstAirlineAddress);
    let flightSuretyApp = await FlightSuretyApp.new(flightSuretyData.address);

    console.log("flightSuretyData.address: " + flightSuretyData.address);
    console.log("flightSuretyApp.address: " + flightSuretyApp.address);

    return {
        owner: owner,
        firstAirlineName: firstAirlineName,
        firstAirlineAddress: firstAirlineAddress,
        weiMultiple: (new BigNumber(10)).pow(18),
        testAddresses: testAddresses,
        flightSuretyData: flightSuretyData,
        flightSuretyApp: flightSuretyApp
    }
}

module.exports = {
    Config: Config
};