// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface INarraLayerVault {
    /**
     * @notice Update supported ERC20 token
     * @param token ERC20 token address
     * @param _weightPerToken Weight per token unit
     */
    function updateSupportedToken(
        address token,
        uint256 _weightPerToken
    ) external;

    /**
     * @notice Remove supported ERC20 token weight
     * @param token ERC20 token address
     */
    function removeSupportedToken(address token) external;

    /**
     * @notice Set cooldown time for staking    
     * @param duration Cooldown duration in seconds
     */
    function setCooldownTime(uint256 duration) external;

    /**
     * @notice Set max count to clean expired stakes
     * @param maxCount The maximum count to clean expired stakes
     */
    function setMaxCountToClean(uint256 maxCount) external;

    /**
     * @notice Clean expired stakes
     * @param maxCount The maximum count to clean expired stakes
     */
    function cleanExpiredStakes(uint256 maxCount) external;

    /**
     * @notice Burn tokens to stake.
     *
     * @param token The address of the token to burn
     * @param amount The amount of tokens to burn
     */
    function burnToStake(address token, uint256 amount) external;
}
