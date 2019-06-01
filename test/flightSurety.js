var Test = require('../config/testConfig.js');
var BigNumber = require('bignumber.js');

contract('Flight Surety Tests', async (accounts) => {
  var config;
  const AIRLINE_FUNDING_VALUE = web3.utils.toWei("10", "ether");
  const timestamp = Math.floor(Date.now() / 1000);
  let airline2 = accounts[2];
  let airline3 = accounts[3];
  let airline4 = accounts[4];
  let airline5 = accounts[5];

  before('setup contract', async () => {
    config = await Test.Config(accounts);
    await config.flightSuretyData.authorizeCaller(config.flightSuretyApp.address);
  });

  describe('(multiparty) test stop loss functionality', function(){
    it(`(multiparty) has correct initial isOperational() value`, async function () {
      // Get operating status
      let status = await config.flightSuretyData.isOperational.call();
      assert.equal(status, true, "Incorrect initial operating status value");
    });

    it(`(multiparty) can block access to setOperatingStatus() for non-Contract Owner account`, async function () {
      // Ensure that access is denied for non-Contract Owner account
      let accessDenied = false;
      try {
        await config.flightSuretyData.setOperatingStatus(false, { from: config.testAddresses[2] });
      }
      catch(e) {
        accessDenied = true;
      }
      assert.equal(accessDenied, true, "Access not restricted to Contract Owner");
    });

    it(`(multiparty) can allow access to setOperatingStatus() for Contract Owner account`, async function () {
      // Ensure that access is allowed for Contract Owner account
      let accessDenied = false;
      try {
        await config.flightSuretyData.setOperatingStatus(false);
      }
      catch(e) {
        accessDenied = true;
      }
      assert.equal(accessDenied, false, "Access not restricted to Contract Owner");

      // Set it back for other tests to work
      await config.flightSuretyData.setOperatingStatus(true);
    });

    it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {
      await config.flightSuretyData.setOperatingStatus(false);

      let reverted = false;
      try {
        await config.flightSurety.isOperational(true);
      }
      catch(e) {
        reverted = true;
      }
      assert.equal(reverted, true, "Access not blocked for requireIsOperational");

      // Set it back for other tests to work
      await config.flightSuretyData.setOperatingStatus(true);
    });
  });

  describe('(airline) test airline functionality', function(){
    // Airline Contract Initialization: First airline is registered when contract is deployed.
    it('(airline) first airline is registered when contract is deployed', async () => {
      let airlineName = await config.flightSuretyData.getAirlineName(config.firstAirlineAddress, { from: config.owner });
      assert.equal(airlineName, config.firstAirlineName, "First airline is not registered when contract is deployed")
    });

    // Airline Ante: Airline can be registered, but does not participate in contract until it submits funding of 10 ether
    it('(airline) cannot register an airline using registerAirline() if it is not funded', async () => {
      try {
        await config.flightSuretyApp.registerAirline("Cebu Pacific Air", airline2, {from: config.firstAirlineAddress});
      }
      catch(e) {
        //console.log(e);
      }
      let result = await config.flightSuretyData.isAirline.call(airline2); 

      assert.equal(result, false, "Airline should not be able to register another airline if it hasn't provided funding");
    });

    // Airline Ante: Airline can be registered, but does not participate in contract until it submits funding of 10 ether
    it('(airline) airline needs to be funded with 10 ether', async () => {
      const AIRLINE_FUNDING_VALUE_LOWER = web3.utils.toWei("5", "ether");

      let reverted = false;
      try {
        await config.flightSuretyApp.fundAirline({ from: config.firstAirlineAddress, value: AIRLINE_FUNDING_VALUE_LOWER, gasPrice: 0 })
      }
      catch(e) {
        reverted = true;
      }

      assert.equal(reverted, true, "Airline cannot be funded with less than 10 ether");
    });

    // Airline Ante: Airline can be registered, but does not participate in contract until it submits funding of 10 ether
    it('(airline) airline does participate in contract when it is funded', async () => {
      await config.flightSuretyApp.fundAirline({ from: config.firstAirlineAddress, value: AIRLINE_FUNDING_VALUE, gasPrice: 0 })

      try {
        await config.flightSuretyApp.registerAirline("Cebu Pacific Air", airline2, {from: config.firstAirlineAddress});
      }
      catch(e) {
        console.log(e);
      }
      let result = await config.flightSuretyData.isAirline.call(airline2); 

      assert.equal(result, true, "Airline should be able to register another airline if it has been funded");
    });

    it('(airline) cannot register an airline more than once', async () => {
      let reverted = false;
      try {
        await config.flightSuretyApp.registerAirline("Cebu Pacific Air", airline2, {from: config.firstAirlineAddress});
      }
      catch(e) {
        reverted = true;
      }

      assert.equal(reverted, true, "Airline cannot be registered twice");
    });

    // Multiparty Consensus: Only existing airline may register a new airline until there are at least four airlines registered
    it('(airline) can register up to 4 airlines', async () => {
      let result = undefined;

      try {
          await config.flightSuretyApp.registerAirline("Philippine Airlines", airline3, {from: config.firstAirlineAddress});
      }
      catch(e) {
        console.log(e);
      }
      result = await config.flightSuretyData.isAirline.call(airline3);
      assert.equal(result, true, "Registering the third airline should be possible");

      try {
          await config.flightSuretyApp.registerAirline("Singapore Airlines", airline4, {from: config.firstAirlineAddress});
      }
      catch(e) {
        console.log(e);
      }
      result = await config.flightSuretyData.isAirline.call(airline4);
      assert.equal(result, true, "Registering the fourth airline should be possible");
    });

    // Multiparty Consensus: Registration of fifth and subsequent airlines requires multi-party consensus of 50% of registered airlines
    it('(airline) single airline cannot register 5th airline on its own', async () => {
      let result = undefined;

      try {
          await config.flightSuretyApp.registerAirline("Cathay Pacific", airline5, {from: config.firstAirlineAddress});
      }
      catch(e) {
        console.log(e);
      }
      result = await config.flightSuretyData.isAirline.call(airline5);
      assert.equal(result, false, "Registering the fifth airline should not be possible");
    });

    it('(airline) 5th airline requires multi-party consensus of 50% of registered airlines', async () => {
      let result = undefined;
      await config.flightSuretyApp.fundAirline({ from: airline2, value: AIRLINE_FUNDING_VALUE, gasPrice: 0 })

      try {
          await config.flightSuretyApp.registerAirline("Cathay Pacific", airline5, {from: airline2});
      }
      catch(e) {
        console.log(e);
      }
      result = await config.flightSuretyData.isAirline.call(airline5);
      assert.equal(result, true, "Registering the fifth airline should be possible");
    });
  });

  describe('(flight) test flight functionality', function(){
    it('(flight) can register new flight', async () => {
      let result = undefined;

      try {
          await config.flightSuretyApp.registerFlight("5J 814", "SIN", "MNL", timestamp,  {from: airline2});
      }
      catch(e) {
        console.log(e);
      }
      result = await config.flightSuretyData.isFlight.call(airline2, "5J 814", timestamp);
      assert.equal(result, true, "Funded airline can register new flight");
    });

    it('(flight) cannot register a flight  more than once', async () => {
      let reverted = false;
      try {
          result = await config.flightSuretyApp.registerFlight("5J 814", "SIN", "MNL", timestamp,  {from: airline2});
      }
      catch(e) {
          reverted = true;
      }

      assert.equal(reverted, true, "Airline cannot register a flight more than once");
    });

    it('(flight) cannot register a flight if the airline is not funded', async () => {
      let reverted = false;
      try {
          result = await config.flightSuretyApp.registerFlight("PR 2543", "MNL", "DGT", timestamp,  {from: airline3});
      }
      catch(e) {
          reverted = true;
      }

      assert.equal(reverted, true, "Airline cannot register a flight if it is not funded");
    });
  });

  describe('(passenger) test passenger functionality', function(){
    it('(passenger) TODO', async () => {
      // TODO
    });
  });
});