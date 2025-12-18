// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DSCEngine public engine;
    DecentralizedStableCoin public dsc;
    DeployDSC public deployer;
    HelperConfig public helperConfig;
    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    address public USER = makeAddr("user");
    uint256 public AMOUNT_COLLATERAL = 10 ether;
    uint256 public STARTING_ERC20_BALANCE = 100 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    //////////////////////////////
    // Constructor Tests /////////
    //////////////////////////////
    address[] public tokenAddresses = new address[](0);
    address[] public priceFeedAddresses = new address[](0);

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testRevertIfDSCAddressIsZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__ZeroAddress.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(0));
    }
    
    function testRevertIfTokenAddressIsZero() public {
        tokenAddresses.push(address(0));
        priceFeedAddresses.push(ethUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__InvalidTokenAddress.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testRevertIfPriceFeedAddressIsZero() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(address(0));
        vm.expectRevert(DSCEngine.DSCEngine__InvalidPriceFeedAddress.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testRevertIfTokenAddressIsDuplicate() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(ethUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__DuplicateToken.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //////////////////////////////
    // Price Tests ///////////////
    //////////////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15 ether;
        uint256 expectedUsd = 45000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usd = 45000e18;
        uint256 expectedTokenAmount = 15 ether;
        uint256 actualTokenAmount = engine.getTokenAmountFromUsd(weth, usd);
        assertEq(actualTokenAmount, expectedTokenAmount);
    }
 
    //////////////////////////////
    // depositCollateral Tests ///
    //////////////////////////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertIfCollateralIsNotAllowed() public {
        ERC20Mock randomToken = new ERC20Mock("RANDOM", "RANDOM", USER, 100 ether);
        vm.startPrank(USER);
        ERC20Mock(randomToken).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalCollateralValueInUsd, uint256 totalDscMinted) = engine.getAccountInfo(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositedAmount = engine.getTokenAmountFromUsd(weth, totalCollateralValueInUsd);
        assertEq(AMOUNT_COLLATERAL, expectedDepositedAmount);
        assertEq(totalDscMinted, expectedTotalDscMinted); 
    }


 
}