const FlightSuretyApp = artifacts.require("FlightSuretyApp");
const FlightSuretyData = artifacts.require("FlightSuretyData");
const fs = require('fs');

module.exports = function(deployer, network, accounts) {
  let firstAirlineName = "Swiss International Airlines";
  let firstAirlineAddress = accounts[1];
  // Airline Contract Initialization: First airline is registered when contract is deployed
  deployer.deploy(FlightSuretyData, firstAirlineName, firstAirlineAddress).then(() => {
    return deployer.deploy(FlightSuretyApp, FlightSuretyData.address).then(() => {
      let config = {
        localhost: {
          url: 'http://localhost:8545',
          dataAddress: FlightSuretyData.address,
          appAddress: FlightSuretyApp.address
        }
      }
      fs.writeFileSync(__dirname + '/../src/dapp/config.json',JSON.stringify(config, null, '\t'), 'utf-8');
      fs.writeFileSync(__dirname + '/../src/server/config.json',JSON.stringify(config, null, '\t'), 'utf-8');
    });
  });
}