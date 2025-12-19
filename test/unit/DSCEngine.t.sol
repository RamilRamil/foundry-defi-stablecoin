// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

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

    function testConstructorRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testConstructorRevertIfDSCAddressIsZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__ZeroAddress.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(0));
    }
    
    function testConstructorRevertIfTokenAddressIsZero() public {
        tokenAddresses.push(address(0));
        priceFeedAddresses.push(ethUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__InvalidTokenAddress.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testConstructorRevertIfPriceFeedAddressIsZero() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(address(0));
        vm.expectRevert(DSCEngine.DSCEngine__InvalidPriceFeedAddress.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testConstructorRevertIfTokenAddressIsDuplicate() public {
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

    ////////////////////////////////////////
    // depositCollateralAndMintDSC Tests ///
    ////////////////////////////////////////
 
     function testDepositCollateralAndMintDSCRevertIfDSCToMintIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, 0);
        vm.stopPrank();
    } 

    function testDepositCollateralAndMintDSCRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        engine.depositCollateralAndMintDSC(weth, 0, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositCollateralAndMintDSCRevertIfCollateralIsNotAllowed() public {
        ERC20Mock randomToken = new ERC20Mock("RANDOM", "RANDOM", USER, 100 ether);
        vm.startPrank(USER);
        ERC20Mock(randomToken).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateralAndMintDSC(address(randomToken), AMOUNT_COLLATERAL, 1);
        vm.stopPrank();
    }

    function testDepositCollateralAndMintDSCSuccess() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        
        // 10 ETH * $3000 = $30,000 collateral
        // Max safe DSC = $30,000 * 50% = $15,000
        uint256 amountDscToMint = 10000e18; // $10,000 DSC - safe amount
        
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDsc(amountDscToMint);
        vm.stopPrank();

        // Verify collateral was deposited
        (uint256 totalCollateralValueInUsd, uint256 totalDscMinted) = engine.getAccountInfo(USER);
        
        assertEq(totalDscMinted, amountDscToMint);
        assertEq(totalCollateralValueInUsd, 30000e18); // 10 ETH * $3000
    }

    ////////////////////////////////////////
    // redeemCollateralForDSC Tests ////////
    ////////////////////////////////////////

    function testRedeemCollateralForDSCRevertIfDSCToBurnIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        engine.redeemCollateralForDSC(weth, AMOUNT_COLLATERAL, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralForDSCRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        engine.redeemCollateralForDSC(weth, 0, 1);
        vm.stopPrank();
    }

    function testRedeemCollateralForDSCSuccess() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        
        // Deposit and mint
        uint256 amountDscToMint = 5000e18; // $5,000 DSC
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDsc(amountDscToMint);
        // Approve DSC for burning
        dsc.approve(address(engine), amountDscToMint);
        
        // Redeem collateral and burn DSC
        uint256 collateralToRedeem = 2 ether; // Redeem 2 ETH
        engine.redeemCollateralForDSC(weth, collateralToRedeem, amountDscToMint);
        vm.stopPrank();

        // Verify balances
        (uint256 totalCollateralValueInUsd, uint256 totalDscMinted) = engine.getAccountInfo(USER);
        
        assertEq(totalDscMinted, 0); // All DSC burned
        assertEq(totalCollateralValueInUsd, 24000e18); // 8 ETH * $3000 = $24,000
    }

    ////////////////////////////////////////
    // redeemCollateral  Tests /////////////
    ////////////////////////////////////////

    function testRedeemCollateralRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertIfCollateralIsNotAllowed() public {
        ERC20Mock randomToken = new ERC20Mock("RANDOM", "RANDOM", USER, 100 ether);
        vm.startPrank(USER);
        ERC20Mock(randomToken).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.redeemCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralSuccess() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        
        uint256 userBalanceBefore = ERC20Mock(weth).balanceOf(USER);
        uint256 collateralToRedeem = 5 ether;
        
        // Redeem collateral
        engine.redeemCollateral(weth, collateralToRedeem);
        vm.stopPrank();

        // Verify collateral was redeemed
        uint256 userBalanceAfter = ERC20Mock(weth).balanceOf(USER);
        (uint256 totalCollateralValueInUsd, ) = engine.getAccountInfo(USER);
        
        assertEq(userBalanceAfter, userBalanceBefore + collateralToRedeem);
        assertEq(totalCollateralValueInUsd, 15000e18); // 5 ETH * $3000 = $15,000
    }

    ////////////////////////////
    // mintDSC  Tests //////////
    ////////////////////////////

    function testMintDSCRevertIfDSCToMintIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        engine.mintDsc(0);
        vm.stopPrank();
    }

    function testMintDSCRevertIfHealthFactorIsBroken() public {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, 0));
        engine.mintDsc(1);
        vm.stopPrank();
    }

    function testMintDSCSuccess() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        
        // 10 ETH * $3000 = $30,000 collateral
        // Max safe DSC = $30,000 * 50% = $15,000
        uint256 amountDscToMint = 10000e18; // $10,000 DSC
        
        engine.mintDsc(amountDscToMint);
        vm.stopPrank();

        // Verify DSC was minted
        (, uint256 totalDscMinted) = engine.getAccountInfo(USER);
        assertEq(totalDscMinted, amountDscToMint);
        assertEq(dsc.balanceOf(USER), amountDscToMint);
    }

    ////////////////////////////
    // burnDSC  Tests //////////
    ////////////////////////////

    function testBurnDSCRevertIfDSCToBurnIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        engine.burnDSC(0);
        vm.stopPrank();
    }

    function testBurnDSCSuccess() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        
        // Deposit and mint
        uint256 amountDscToMint = 5000e18; // $5,000 DSC
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDsc(amountDscToMint);
        // Approve DSC for burning
        dsc.approve(address(engine), amountDscToMint);
        
        // Burn DSC
        engine.burnDSC(amountDscToMint);
        vm.stopPrank();

        // Verify DSC was burned
        (, uint256 totalDscMinted) = engine.getAccountInfo(USER);
        assertEq(totalDscMinted, 0);
        assertEq(dsc.balanceOf(USER), 0);
    }

    ////////////////////////////
    // liquidate  Tests ////////
    ////////////////////////////

    function testLiquidateRevertIfHealthFactorIsOk() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(USER, weth, 1);
        vm.stopPrank();
    }

    // 1. Revert if debtToCover = 0
    function testLiquidateRevertsIfDebtToCoverIsZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__MoreThanZero.selector);
        engine.liquidate(USER, weth, 0);
    }

    // 2. Successful liquidation when health factor < 1
    function testLiquidateSucceedsWhenHealthFactorBroken() public {
        // Setup: USER deposits collateral and mints DSC
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        // 10 ETH * $3000 = $30,000 collateral
        // Max safe DSC = $30,000 * 50% = $15,000
        // Mint safe amount
        engine.mintDsc(15000e18);
        vm.stopPrank();

        // Drop ETH price from $3000 to $2000, so health factor falls < 1
        // New collateral value: 10 ETH * $2000 = $20,000
        // DSC minted: $15,000
        // Health factor: ($20,000 * 0.5) / $15,000 = 0.666... < 1
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(2000e8);

        // Verify that health factor is actually < 1
        (uint256 collateralValueInUsd, uint256 totalDscMinted) = engine.getAccountInfo(USER);
        assertGt(totalDscMinted, collateralValueInUsd / 2); // More than 50% threshold

        // Setup liquidator (just mint DSC tokens without debt)
        address liquidator = makeAddr("liquidator");
        vm.startPrank(liquidator);
        
        // Give liquidator DSC tokens directly (not through mint with debt)
        vm.stopPrank();
        vm.prank(address(engine));
        dsc.mint(liquidator, 10000e18);
        
        vm.startPrank(liquidator);
        dsc.approve(address(engine), 5000e18);

        // Liquidate part of the debt
        engine.liquidate(USER, weth, 5000e18);
        vm.stopPrank();

        // Verify that liquidation happened
        (, uint256 dscAfter) = engine.getAccountInfo(USER);
        assertEq(dscAfter, 15000e18 - 5000e18);
    }

    // 3. Verify correct collateral calculation with 10% bonus
    function testLiquidateCalculatesCorrectCollateralWithBonus() public {
        // Setup undercollateralized USER
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDsc(15000e18);
        vm.stopPrank();

        // Drop ETH price from $3000 to $2000, so health factor falls < 1
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(2000e8);

        // Setup liquidator (just mint DSC tokens without debt)
        address liquidator = makeAddr("liquidator");
        vm.stopPrank();
        vm.prank(address(engine));
        dsc.mint(liquidator, 10000e18);
        
        vm.startPrank(liquidator);
        dsc.approve(address(engine), 5000e18);

        uint256 debtToCover = 5000e18;
        
        // Calculate expected collateral (at new price $2000)
        // $5000 / $2000 per ETH = 2.5 ETH
        uint256 expectedTokenAmount = engine.getTokenAmountFromUsd(weth, debtToCover);
        // 10% bonus: 2.5 * 0.1 = 0.25 ETH
        uint256 expectedBonus = (expectedTokenAmount * 10) / 100;
        uint256 expectedTotal = expectedTokenAmount + expectedBonus;

        uint256 liquidatorWethBefore = ERC20Mock(weth).balanceOf(liquidator);
        
        engine.liquidate(USER, weth, debtToCover);
        
        uint256 liquidatorWethAfter = ERC20Mock(weth).balanceOf(liquidator);
        uint256 actualReceived = liquidatorWethAfter - liquidatorWethBefore;

        assertEq(actualReceived, expectedTotal);
        vm.stopPrank();
    }

    // 4. Collateral transfers from user to liquidator
    function testLiquidateTransfersCollateralToLiquidator() public {
        // Setup undercollateralized USER
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDsc(15000e18);
        vm.stopPrank();

        // Drop ETH price from $3000 to $2000, so health factor falls < 1
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(2000e8);

        // Setup liquidator (just mint DSC tokens without debt)
        address liquidator = makeAddr("liquidator");
        vm.stopPrank();
        vm.prank(address(engine));
        dsc.mint(liquidator, 10000e18);
        
        vm.startPrank(liquidator);
        dsc.approve(address(engine), 5000e18);

        uint256 liquidatorBalanceBefore = ERC20Mock(weth).balanceOf(liquidator);
        
        engine.liquidate(USER, weth, 5000e18);
        
        uint256 liquidatorBalanceAfter = ERC20Mock(weth).balanceOf(liquidator);
        
        // Verify that liquidator received collateral
        assertGt(liquidatorBalanceAfter, liquidatorBalanceBefore);
        vm.stopPrank();
    }

    // 5. DSC is burned from user (debt decreases)
    function testLiquidateBurnsDSCFromUser() public {
        // Setup undercollateralized USER
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDsc(15000e18);
        vm.stopPrank();

        // Drop ETH price from $3000 to $2000, so health factor falls < 1
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(2000e8);

        (, uint256 userDscBefore) = engine.getAccountInfo(USER);

        // Setup liquidator (just mint DSC tokens without debt)
        address liquidator = makeAddr("liquidator");
        vm.stopPrank();
        vm.prank(address(engine));
        dsc.mint(liquidator, 10000e18);
        
        uint256 debtToCover = 5000e18;
        vm.startPrank(liquidator);
        dsc.approve(address(engine), debtToCover);

        engine.liquidate(USER, weth, debtToCover);
        vm.stopPrank();

        (, uint256 userDscAfter) = engine.getAccountInfo(USER);
        
        // Verify that USER's debt decreased by debtToCover
        assertEq(userDscBefore - userDscAfter, debtToCover);
    }

    // 6. User's collateral decreases
    function testLiquidateReducesUserCollateral() public {
        // Setup undercollateralized USER
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDsc(15000e18);
        vm.stopPrank();

        // Drop ETH price from $3000 to $2000, so health factor falls < 1
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(2000e8);

        (uint256 userCollateralBefore, ) = engine.getAccountInfo(USER);

        // Setup liquidator (just mint DSC tokens without debt)
        address liquidator = makeAddr("liquidator");
        vm.stopPrank();
        vm.prank(address(engine));
        dsc.mint(liquidator, 10000e18);
        
        vm.startPrank(liquidator);
        dsc.approve(address(engine), 5000e18);

        engine.liquidate(USER, weth, 5000e18);
        vm.stopPrank();

        (uint256 userCollateralAfter, ) = engine.getAccountInfo(USER);
        
        // Verify that USER's collateral decreased
        assertLt(userCollateralAfter, userCollateralBefore);
    }
    
}