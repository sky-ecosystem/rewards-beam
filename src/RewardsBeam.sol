// SPDX-FileCopyrightText: © 2026 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.24;

interface VestedRewardsDistributionLike {
    function dssVest() external view returns (address);
    function vestId() external view returns (uint256);
    function file(bytes32, uint256) external;
    function distribute() external returns (uint256);
}

interface DssVestLike {
    function TWENTY_YEARS() external view returns (uint256);
    function unpaid(uint256) external view returns (uint256);
    function create(address, uint256, uint256, uint256, uint256, address) external returns (uint256);
    function restrict(uint256) external;
    function yank(uint256) external;
}

/// @title  RewardsBeam
/// @notice Lets a facilitator multisig re-rate the vesting stream that funds a treasury-funded farm,
///         within boundaries set by Sky governance. It is the on-chain equivalent of the
///         `TreasuryFundedFarmingInit.updateFarmVest` routine used in governance spells.
/// @dev    Governance is expected to `rely` this contract on both `vest` and `dist`. See README.md.
contract RewardsBeam {
    // --- storage variables ---

    mapping(address => uint256) public wards;
    mapping(address => uint256) public buds;
    uint256 public maxVestTot; // [wad]     Maximum allowed total amount of a new vesting stream
    uint256 public vestTau;    // [seconds] Duration of a new vesting stream
    uint64  public tau;        // Cooldown period between set() calls in seconds
    uint128 public toc;        // Last time when set() was called (Unix timestamp)

    // --- immutables ---

    VestedRewardsDistributionLike public immutable dist;
    DssVestLike public immutable vest;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event Set(uint256 indexed prevVestId, uint256 indexed vestId, uint256 vestTot, uint256 vestTau);

    // --- modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "RewardsBeam/not-authorized");
        _;
    }

    modifier toll() {
        require(buds[msg.sender] == 1, "RewardsBeam/not-facilitator");
        _;
    }

    // --- constructor ---

    constructor(address _dist) {
        dist = VestedRewardsDistributionLike(_dist);
        vest = DssVestLike(dist.dssVest());
        vestTau = 90 days;
        emit File("vestTau", 90 days);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- administration ---

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function kiss(address usr) external auth {
        buds[usr] = 1;
        emit Kiss(usr);
    }

    function diss(address usr) external auth {
        buds[usr] = 0;
        emit Diss(usr);
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "maxVestTot") {
            maxVestTot = data;
        } else if (what == "vestTau") {
            require(data > 0 && data <= vest.TWENTY_YEARS(), "RewardsBeam/vestTau-out-of-boundaries");
            vestTau = data;
        } else if (what == "tau") {
            require(data <= type(uint64).max, "RewardsBeam/invalid-tau-value");
            tau = uint64(data);
        } else if (what == "toc") {
            require(data <= type(uint128).max, "RewardsBeam/invalid-toc-value");
            toc = uint128(data);
        } else {
            revert("RewardsBeam/file-unrecognized-param");
        }
        emit File(what, data);
    }

    // --- execution ---

    function set(uint256 vestTot) external toll {
        uint256 vestTau_ = vestTau;

        require(block.timestamp >= tau + toc, "RewardsBeam/too-early");
        require(vestTot <= maxVestTot, "RewardsBeam/vestTot-above-max");

        toc = uint128(block.timestamp);

        uint256 prevVestId = dist.vestId();

        // Flush whatever the outgoing stream still owes the farm before retiring it.
        if (vest.unpaid(prevVestId) > 0) {
            dist.distribute();
        }
        vest.yank(prevVestId);

        // Begins now (`bgn` is now and `eta` is 0, so no cliff), so nothing has accrued yet:
        // the distribution job picks it up from here.
        // No manager (`mgr` is address(0)): its `yank` would be pointless here, since a bud
        // can start a new stream with the next `set()`.
        uint256 vestId = vest.create(address(dist), vestTot, block.timestamp, vestTau_, 0, address(0));
        vest.restrict(vestId);
        dist.file("vestId", vestId);

        emit Set(prevVestId, vestId, vestTot, vestTau_);
    }
}
