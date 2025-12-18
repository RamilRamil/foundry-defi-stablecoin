// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract DSCEngine is ReentrancyGuard {
    ////////////// 
    // errors
    ///////////// 
    error DSCEngine__MoreThanZero();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__ExcessDebtToCover();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__InvalidDSCAddress();
    error DSCEngine__DuplicateToken();
    error DSCEngine__ZeroAddress();
    error DSCEngine__InvalidTokenAddress();
    error DSCEngine__InvalidPriceFeedAddress();

    ////////////// 
    // state variables
    ////////////// 

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATION_BONUS = 10;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;


    ////////////// 
    // events
    ////////////// 
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);

    ////////////// 
    // modifiers
    ////////////// 
    modifier moreThanZero(uint256 value) {
        if (value <= 0) {
            revert DSCEngine__MoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ////////////// 
    // functions
    ////////////// 

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        if (dscAddress == address(0)) {
            revert DSCEngine__ZeroAddress();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            if (tokenAddresses[i] == address(0)) {
                revert DSCEngine__InvalidTokenAddress();
            }
            if (priceFeedAddresses[i] == address(0)) {
                revert DSCEngine__InvalidPriceFeedAddress();
            }
            if (s_priceFeeds[tokenAddresses[i]] != address(0)) {
                revert DSCEngine__DuplicateToken();
            }
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////// 
    // External functions
    ////////////// 

    /*
    * @param tokenCollateralAddress The address of the token to deposit as collateral
    * @param amountCollateral The amount of collateral to deposit
    * @param amountDscToMint The amount of DSC to mint
    * @notice This function deposits collateral and mints DSC in one transaction
    */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint) 
        external 
        moreThanZero(amountCollateral)
        moreThanZero(amountDscToMint)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant{
            depositCollateral(tokenCollateralAddress, amountCollateral);
            mintDsc(amountDscToMint);
        }

    /*
    * @param tokenCollateralAddress The address of the token to deposit as collateral
    * @param amountCollateral The amount of collateral to deposit
    *
    */
    function depositCollateral(
        address tokenCollateralAddress, 
        uint256 amountCollateral) 
        public 
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant{

        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*
    * @param tokenCollateralAddress The address of the token to redeem as collateral
    * @param amountCollateral The amount of collateral to redeem
    * @param amountDSCToBurn The amount of DSC to burn
    * @notice This function redeems collateral and burns DSC in one transaction
    */
    function redeemCollateralForDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToBurn) external {
            burnDSC(amountDSCToBurn);
            redeemCollateral(tokenCollateralAddress, amountCollateral);
        }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant{
            _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
            _revertIfHealthFactorIsBroken(msg.sender);
        } 

    /*
    * @param amountDscToMint The amount of DSC to mint
    */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) nonReentrant {
        _burnDSC(msg.sender, msg.sender, amountDscToBurn);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
    * @param user The address of the user to liquidate
    * @param tokenCollateralAddress The address of the token to liquidate as collateral
    * @param debtToCover The amount of debt to cover
    * @notice This function liquidates a user's collateral and burns DSC in one transaction, you can partially liquidate a user's position
    */
    function liquidate(
        address user,
        address tokenCollateralAddress,
        uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant{
            uint256 startingUserHealthFactor = _healthFactor(user);
            if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
                revert DSCEngine__HealthFactorOk();
            }
            uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(tokenCollateralAddress, debtToCover);
            uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
            uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
            
            _redeemCollateral(user, msg.sender, tokenCollateralAddress, totalCollateralToRedeem);
            _burnDSC(user, msg.sender, debtToCover);

            uint256 endingUserHealthFactor = _healthFactor(user);
            if (endingUserHealthFactor <= startingUserHealthFactor) {
                revert DSCEngine__HealthFactorNotImproved();
            }
            _revertIfHealthFactorIsBroken(msg.sender);
        }


   ////////////// 
    // Private and Internal view functions
    ////////////// 

    /*
    * @param onBehalfOf The address of the user who is burning the DSC
    * @param dscFrom The address of the user who is sending the DSC
    * @param amountDscToBurn The amount of DSC to burn
    * @notice This function burns DSC from an address and updates the user's DSC minted amount 
    */
    function _burnDSC(address onBehalfOf, address dscFrom, uint256 amountDscToBurn) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;

        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) {
        totalDscMinted = s_DSCMinted[user];
        totalCollateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) internal view returns (uint256) {
        //total DSC Minted
        //total collateral value
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(user); 
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold = (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken(healthFactor);
        }
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral) internal {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    ////////////// 
    // Public and External view functions
    ////////////// 

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) private view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have deposited, and map it to
        // the price, to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    function getAccountInfo(address user) external view returns (uint256 totalCollateralValueInUsd, uint256 totalDscMinted) {
        (totalDscMinted, totalCollateralValueInUsd) = _getAccountInformation(user);
    }

}