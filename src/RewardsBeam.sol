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

pragma solidity ^0.8.21;

interface VestedRewardsDistributionLike {
    function dssVest() external view returns (address);
    function vestId() external view returns (uint256);
    function file(bytes32, uint256) external;
    function distribute() external returns (uint256);
}

interface DssVestTransferrableLike {
    function cap() external view returns (uint256);
    function unpaid(uint256) external view returns (uint256);
    function create(address, uint256, uint256, uint256, uint256, address) external returns (uint256);
    function restrict(uint256) external;
    function yank(uint256) external;
}

/// @title  RewardsBeam
/// @notice Lets a facilitator multisig re-rate the vesting stream that funds a treasury-funded farm,
///         within boundaries set by Sky governance. It is the on-chain equivalent of the
///         `TreasuryFundedFarmingInit.updateFarmVest` routine used in governance spells.
/// @dev    Governance is expected to `rely` this contract on both `vest` and `dist`, and to keep the
///         treasury funded and its rewards-token allowance to `vest` topped up. `maxVestTot` is the
///         beam's own boundary; that allowance independently caps the cumulative amount that can ever
///         be transferred out, enforced by the token on each distribution.
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
    DssVestTransferrableLike public immutable vest;

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
        vest = DssVestTransferrableLike(dist.dssVest());
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
            require(data > 0, "RewardsBeam/vestTau-zero");
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

    // Notes:
    // - It is intended to rewrite the same values, emit the event, and reset the toc count, even if there is no change.
    // - A fresh beam is inert: maxVestTot defaults to 0, so governance must file the boundary before a
    //   facilitator can do anything. vestTau defaults to 90 days, the value every spell has used.
    // - The facilitator sets one number: how much to stream. The duration is `vestTau`, which only governance can
    //   file, so the emission rate a facilitator can reach is bounded by maxVestTot / vestTau and both ends of that
    //   are governance-owned. Lowering `vestTot` is unbounded; at worst it starves the farm, which governance can
    //   revive, and the funds simply stay in the treasury.
    // - The new stream always begins at `block.timestamp`, as every spell that ran this routine did. Keeping it
    //   hardcoded removes the only knob a facilitator could have used to shift emissions in time: a `bgn` in the
    //   past would make part of the stream claimable on creation and drop it into the farm at once, and a `bgn`
    //   in the future would stall emissions until it arrives.
    // - The treasury allowance to `vest` is neither raised nor checked here. The beam is not the treasury and
    //   cannot approve on its behalf, and a pre-flight check would be worth little: the allowance is a
    //   bookkeeping figure that the treasury balance does not necessarily back, `DssVest` draws `unpaid`
    //   progressively rather than `vestTot` at once, and the token already caps cumulative transfers on its own.
    //   The funding check that matters happens for free: the flush below moves real tokens, so `set()` reverts
    //   if the treasury cannot cover what is currently due. Keeping the stream payable from there on is
    //   governance's job, exactly as it is when the treasury balance runs low.
    // - `vest.cap()` is an independent governance-owned rate ceiling that `vest.create` enforces anyway; it is
    //   checked up front only so the failure mode is legible. The beam is deliberately not a `cap` filer:
    //   raising it would affect every stream of the vest, not just this farm's.
    // - The farm's `rewardsDuration` is deliberately left out of the knobs: re-rating the notification window is
    //   a more structural decision, better routed through the full governance process.
    function set(uint256 vestTot) external toll {
        uint256 vestTau_ = vestTau;

        require(block.timestamp >= tau + toc, "RewardsBeam/too-early");
        require(vestTot > 0, "RewardsBeam/vestTot-zero");
        require(vestTot <= maxVestTot, "RewardsBeam/vestTot-above-max");
        require(vestTot / vestTau_ <= vest.cap(), "RewardsBeam/rate-above-vest-cap");

        toc = uint128(block.timestamp);

        uint256 prevVestId = dist.vestId();
        require(prevVestId != 0, "RewardsBeam/dist-vest-id-not-set");

        // Flush whatever the outgoing stream still owes the farm before retiring it.
        if (vest.unpaid(prevVestId) > 0) {
            dist.distribute();
        }
        vest.yank(prevVestId);

        // Note: no distribution follows. The stream begins now, so nothing has accrued yet and
        // `vest.unpaid(vestId)` is necessarily 0; the distribution job picks it up from here.
        uint256 vestId = vest.create(address(dist), vestTot, block.timestamp, vestTau_, 0, address(0));
        vest.restrict(vestId);
        dist.file("vestId", vestId);

        emit Set(prevVestId, vestId, vestTot, vestTau_);
    }
}
