// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

interface DssVestMockLike {
    function usr(uint256) external view returns (address);
    function bgn(uint256) external view returns (uint256);
    function clf(uint256) external view returns (uint256);
    function res(uint256) external view returns (uint256);
    function tot(uint256) external view returns (uint256);
    function rxd(uint256) external view returns (uint256);
    function unpaid(uint256) external view returns (uint256);
    function vest(uint256, uint256) external;
}

// Models the parts of VestedRewardsDistribution that RewardsBeam relies on, keeping its revert
// conditions for `file("vestId", ...)` and `distribute()`. It abstracts the payment away: the
// rewards are not transferred to the farm and `notifyRewardAmount` is not called.
contract VestedRewardsDistributionMock {
    mapping (address => uint256) public wards;
    DssVestMockLike public dssVest;
    uint256 public vestId;
    uint256 public lastDistributedAt;

    function file(bytes32 what, uint256 data) external {
        require(wards[msg.sender] == 1, "VestedRewardsDistribution/not-authorized");
        require(what == "vestId",       "VestedRewardsDistribution/file-unrecognized-param");
        // _setVestId
        require(dssVest.tot(data) > dssVest.rxd(data),    "VestedRewardsDistribution/invalid-vest-id");
        require(dssVest.res(data) == 1,                   "VestedRewardsDistribution/invalid-vest-res");
        require(dssVest.usr(data) == address(this),       "VestedRewardsDistribution/invalid-vest-usr");
        require(dssVest.clf(data) == dssVest.bgn(data),   "VestedRewardsDistribution/invalid-vest-cliff");
        vestId = data;
        lastDistributedAt = 0;
    }

    function distribute() external returns (uint256 amount) {
        require(vestId != 0, "VestedRewardsDistribution/invalid-vest-id");
        amount = dssVest.unpaid(vestId);
        require(amount > 0, "VestedRewardsDistribution/no-pending-amount");
        lastDistributedAt = block.timestamp;
        dssVest.vest(vestId, amount);
    }
}
