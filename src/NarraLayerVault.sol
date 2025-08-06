// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {INarraLayerVault} from "./interfaces/INarraLayerVault.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IRewardVaultFactory.sol";
import "./interfaces/IRewardVault.sol";
import "./token/StakingToken.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title NarraLayerVault
 * @dev A vault contract supporting multiple tokens, receipt issuance, and reward claiming.
 *      Integrates with staking, reward vault, and BeraPawForge for reward minting.
 *      Uses role-based access control for admin and upgrade operations.
 *
 * @notice This contract allows users to:
 *         1. Burn supported tokens to receive receipts
 *         2. Claim rewards after cooldown period
 *         3. Admin can manage supported tokens and cooldown time
 */
contract NarraLayerVault is
    INarraLayerVault,
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    address public rewardVaultFactory;
    address public stakingTokenAddress;
    address public rewardVault;

    uint256 public cooldownTime; // default set in initialize()
    mapping(address => uint256) public supportedTokens; // weight per token

    uint256 public nextReceiptID;
    uint256 public nextToCleanReceiptID;
    uint256 public maxCountToClean; // default set in initialize()
    mapping(uint256 => Receipt) public receipts;

    /**
     * @dev Struct for initialization parameters.
     * @param defaultAdmin The address to be granted admin roles.
     * @param rewardVaultFactory The address of the reward vault factory.
     */
    struct InitParams {
        address defaultAdmin;
        address rewardVaultFactory;
    }

    /**
     * @dev Struct representing a user's receipt for staking.
     * @param user The address of the user.
     * @param token The address of the staked token.
     * @param receiptWeight The calculated weight for the receipt.
     * @param clearedAt The timestamp after which the staking can be cleared.
     * @param cleared Whether the staking has been cleared.
     */
    struct Receipt {
        address user;
        address token;
        uint256 receiptWeight;
        uint256 clearedAt;
        bool cleared;
    }

    event CooldownTimeUpdated(uint256 newCooldownTime);
    event SupportedTokenUpdated(address indexed token, uint256 weightPerToken);
    event BurnToStake(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 receiptID
    );
    event MaxCountToCleanUpdated(uint256 maxCount);

    event ReceiptClaimed(address indexed user, uint256 indexed receiptID);
    event StakingTokenCreated(address stakingToken);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with the given parameters.
     *      Sets up roles, staking token, and reward vault.
     *
     * @param params The initialization parameters containing:
     *        - defaultAdmin: Address that will be granted admin roles (must not be zero address)
     *        - rewardVaultFactory: Address of the reward vault factory (must not be zero address)
     *
     * @notice This function can only be called once during contract deployment
     */
    function initialize(InitParams calldata params) public initializer {
        require(params.defaultAdmin != address(0), "Invalid admin address");
        require(
            params.rewardVaultFactory != address(0),
            "Invalid factory address"
        );

        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, params.defaultAdmin);
        _grantRole(UPGRADER_ROLE, params.defaultAdmin);
        _grantRole(ADMIN_ROLE, params.defaultAdmin);
        rewardVaultFactory = params.rewardVaultFactory;

        // Set default values for proxy storage
        cooldownTime = 7 days;
        maxCountToClean = 100;
    }

    /**
     * @notice Setup staking token and reward vault
     * @dev This function can only be called by addresses with ADMIN_ROLE
     * @dev This function will create a new staking token and a new reward vault
     * @dev This function will set the staking token address and the reward vault address
     * @dev This function will emit a StakingTokenCreated event
     * @dev This function will emit a RewardVaultCreated event
     */
    function setupStakingToken() external override onlyRole(ADMIN_ROLE) {
        // Create new staking token
        StakingToken stakingToken = new StakingToken();
        stakingTokenAddress = address(stakingToken);
        emit StakingTokenCreated(stakingTokenAddress);

        // Create vault for newly created token
        address vaultAddress = IRewardVaultFactory(rewardVaultFactory)
            .createRewardVault(address(stakingToken));

        rewardVault = address(IRewardVault(vaultAddress));
    }

    /**
     * @dev Authorizes contract upgrades. Only callable by UPGRADER_ROLE.
     *
     * @param newImplementation The address of the new implementation contract
     * @notice This function is part of the UUPS upgrade pattern
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @notice Update the weight per token for a supported token.
     *
     * @param token The address of the token to update
     * @param _weightPerToken The new weight per token
     *
     * @notice This function:
     *         1. Can only be called by addresses with ADMIN_ROLE
     *         2. Weight is stored as a multiplier of 1e4 for precision
     *         3. Setting weight to 0 effectively removes the token
     *
     * @custom:emits SupportedTokenUpdated event
     */
    function updateSupportedToken(
        address token,
        uint256 _weightPerToken
    ) external override onlyRole(ADMIN_ROLE) {
        require(token != address(0), "Token address cannot be zero");
        require(
            token != stakingTokenAddress,
            "Cannot add staking token as supported token"
        );
        require(_weightPerToken > 0, "Weight must be greater than zero");
        supportedTokens[token] = _weightPerToken;
        emit SupportedTokenUpdated(token, _weightPerToken);
    }

    /**
     * @notice Remove a token from the list of supported tokens. implement this function when this erc20 token violates certain rules
     *
     * @param token The address of the token to remove
     *
     * @notice This function:
     *         1. Can only be called by addresses with ADMIN_ROLE
     *         2. Effectively sets the token's weight to 0
     *
     * @custom:emits SupportedTokenUpdated event with weight 0
     */
    function removeSupportedToken(
        address token
    ) external override onlyRole(ADMIN_ROLE) {
        require(token != address(0), "Token address cannot be zero");
        require(
            token != stakingTokenAddress,
            "Cannot remove staking token as supported token"
        );
        delete supportedTokens[token];
        emit SupportedTokenUpdated(token, 0);
    }

    /**
     * @notice Set the cooldown time for claiming rewards.
     *
     * @param duration The new cooldown duration in seconds
     *
     * @notice This function:
     *         1. Can only be called by addresses with ADMIN_ROLE
     *         2. Duration must be greater than 0
     *         3. Default cooldown time is 7 days
     *
     * @custom:emits CooldownTimeUpdated event
     */
    function setCooldownTime(
        uint256 duration
    ) external override onlyRole(ADMIN_ROLE) {
        require(duration > 0, "Cooldown time must be greater than 0");
        cooldownTime = duration;
        emit CooldownTimeUpdated(duration);
    }

    /**
     * @notice Set the maximum count to clean expired stakes.
     *
     * @param maxCount The new maximum count to clean expired stakes
     *
     * @notice This function:
     *         1. Can only be called by addresses with ADMIN_ROLE
     *         2. Max count must be greater than 0
     *         3. Default max count is 100
     */
    function setMaxCountToClean(
        uint256 maxCount
    ) external override onlyRole(ADMIN_ROLE) {
        require(maxCount > 0, "Max count must be greater than 0");
        maxCountToClean = maxCount;
        emit MaxCountToCleanUpdated(maxCount);
    }

    /**
     * @notice Burn tokens to stake.
     *
     * @param token The address of the token to burn
     * @param amount The amount of tokens to burn
     *
     * @notice This function:
     *         2. Amount must be greater than 0
     *         3. Token must be supported
     *         4. Burn token to get receipt
     *         5. Mint staking token
     *         6. Approve reward vault to spend staking token
     *         7. Delegate stake to reward vault
     *         8. Create receipt record
     *         9. Clear expired stakes
     */
    function burnToStake(address token, uint256 amount) external override nonReentrant {
        require(token != stakingTokenAddress, "Cannot stake the staking token itself");
        require(amount > 0, "Amount must be greater than 0");
        require(supportedTokens[token] > 0, "Unsupported token");
        // Burn token to get receipt
        IERC20(token).safeTransferFrom(msg.sender, address(0xdead), amount);

        uint256 receiptWeight = amount * supportedTokens[token]; // weight * amount = need mint staking token
        StakingToken(stakingTokenAddress).mint(address(this), receiptWeight);

        StakingToken(stakingTokenAddress).approve(rewardVault, receiptWeight);
        IRewardVault(rewardVault).delegateStake(msg.sender, receiptWeight);

        // Create receipt record
        uint256 receiptID = nextReceiptID++;
        receipts[receiptID] = Receipt({
            user: msg.sender,
            token: token,
            receiptWeight: receiptWeight,
            clearedAt: block.timestamp + cooldownTime, // record delegateStake time
            cleared: false
        });

        _clearStaking();

        emit BurnToStake(msg.sender, token, amount, receiptID);
    }

    function _cleanExpiredStakes(uint256 maxCount) internal {
        require(maxCount <= maxCountToClean, "Max count must be less than or equal to max count to clean");
        uint256 cleaned = 0;
        while (nextToCleanReceiptID < nextReceiptID && cleaned < maxCount) {
            Receipt storage receipt = receipts[nextToCleanReceiptID];
            if (receipt.cleared) {
                // Already cleared, skip to next
                nextToCleanReceiptID++;
            } else if (block.timestamp > receipt.clearedAt) {
                // Eligible for cleaning
                IRewardVault(rewardVault).delegateWithdraw(
                    receipt.user,
                    receipt.receiptWeight
                );
                receipt.cleared = true;
                emit ReceiptClaimed(receipt.user, nextToCleanReceiptID);
                cleaned++;
                nextToCleanReceiptID++;
            } else {
                // Not yet eligible, stop here
                break;
            }
        }
    }

    function cleanExpiredStakes(uint256 maxCount) external override nonReentrant {
        require(maxCount > 0, "Max count must be greater than zero");
        _cleanExpiredStakes(maxCount);
    }

    function _clearStaking() internal {
        _cleanExpiredStakes(maxCountToClean);
    }

    function claimReceipt(uint256 receiptID) external nonReentrant {
        Receipt storage receipt = receipts[receiptID];
        require(!receipt.cleared, "Already cleared");
        require(receipt.user == msg.sender, "Not receipt owner");
        require(block.timestamp > receipt.clearedAt, "Cooldown not passed");

        IRewardVault(rewardVault).delegateWithdraw(receipt.user, receipt.receiptWeight);
        receipt.cleared = true;
        emit ReceiptClaimed(msg.sender, receiptID);
    }

}
