// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {RewardsBeam} from "../src/RewardsBeam.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface DssVestLike {
    function rely(address) external;
    function cap() external view returns (uint256);
    function czar() external view returns (address);
    function ids() external view returns (uint256);
    function usr(uint256) external view returns (address);
    function bgn(uint256) external view returns (uint256);
    function clf(uint256) external view returns (uint256);
    function fin(uint256) external view returns (uint256);
    function res(uint256) external view returns (uint256);
    function tot(uint256) external view returns (uint256);
    function rxd(uint256) external view returns (uint256);
    function unpaid(uint256) external view returns (uint256);
    function valid(uint256) external view returns (bool);
}

interface DistLike {
    function rely(address) external;
    function dssVest() external view returns (address);
    function gem() external view returns (address);
    function stakingRewards() external view returns (address);
    function vestId() external view returns (uint256);
    function lastDistributedAt() external view returns (uint256);
}

interface FarmLike {
    function rewardRate() external view returns (uint256);
    function periodFinish() external view returns (uint256);
    function rewardsDuration() external view returns (uint256);
    function rewardsDistribution() external view returns (address);
}

interface GemLike {
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function allowance(address, address) external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
}

contract RewardsBeamTest is Test {
    ChainlogLike constant chainlog = ChainlogLike(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
    uint256 constant FORK_BLOCK = 25_920_000;

    DssVestLike vest;
    DistLike dist;
    FarmLike farm;
    GemLike gem;
    address pauseProxy;
    RewardsBeam beam;

    address facilitator = address(0xFAC1);
    address rando = address(0xDEAD);

    uint256 constant MAX_VEST_TOT = 150_000_000 ether;
    uint256 constant VEST_TAU = 90 days;
    uint256 constant COOLDOWN = 7 days;

    event Rely(address indexed usr);
    event Kiss(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event Set(uint256 indexed prevVestId, uint256 indexed vestId, uint256 vestTot, uint256 vestTau);

    function setUp() public {
        string memory rpc = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            // Locally, skip when no RPC is configured. In CI, fail loudly rather than
            // reporting a green run that executed nothing.
            require(!vm.envOr("CI", false), "RewardsBeamTest/ETH_RPC_URL-required-in-ci");
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc, FORK_BLOCK);

        pauseProxy = chainlog.getAddress("MCD_PAUSE_PROXY");
        dist = DistLike(chainlog.getAddress("REWARDS_DIST_LSSKY_SKY"));
        vest = DssVestLike(chainlog.getAddress("MCD_VEST_SKY_TREASURY"));
        farm = FarmLike(chainlog.getAddress("REWARDS_LSSKY_SKY"));
        gem = GemLike(chainlog.getAddress("SKY"));

        // Sanity: the wiring the beam assumes is the wiring that is actually deployed.
        assertEq(dist.dssVest(), address(vest));
        assertEq(dist.stakingRewards(), address(farm));
        assertEq(dist.gem(), address(gem));
        assertEq(vest.czar(), pauseProxy);
        assertEq(farm.rewardsDistribution(), address(dist));

        beam = new RewardsBeam(address(dist));

        // What the governance spell would do.
        vm.startPrank(pauseProxy);
        vest.rely(address(beam));
        dist.rely(address(beam));
        vm.stopPrank();

        beam.file("maxVestTot", MAX_VEST_TOT);
        beam.file("tau", COOLDOWN);
        beam.kiss(facilitator);
    }

    // --- deployment ---

    function testConstructor() public view {
        assertEq(address(beam.dist()), address(dist));
        assertEq(address(beam.vest()), address(vest));
        assertEq(beam.vestTau(), VEST_TAU);
        assertEq(beam.wards(address(this)), 1);
    }

    function testFreshBeamIsInert() public {
        RewardsBeam fresh = new RewardsBeam(address(dist));
        assertEq(fresh.maxVestTot(), 0);
        assertEq(fresh.vestTau(), VEST_TAU);
        assertEq(fresh.tau(), 0);
        assertEq(fresh.toc(), 0);

        fresh.kiss(facilitator);
        vm.prank(facilitator);
        vm.expectRevert("RewardsBeam/vestTot-above-max");
        fresh.set(1 ether);
    }

    // --- administration ---

    function testRelyDeny() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(rando);
        beam.rely(rando);
        assertEq(beam.wards(rando), 1);
        beam.deny(rando);
        assertEq(beam.wards(rando), 0);
    }

    function testKissDiss() public {
        vm.expectEmit(true, true, true, true);
        emit Kiss(rando);
        beam.kiss(rando);
        assertEq(beam.buds(rando), 1);
        beam.diss(rando);
        assertEq(beam.buds(rando), 0);
    }

    function testAdminAuth() public {
        vm.startPrank(rando);
        vm.expectRevert("RewardsBeam/not-authorized");
        beam.rely(rando);
        vm.expectRevert("RewardsBeam/not-authorized");
        beam.deny(rando);
        vm.expectRevert("RewardsBeam/not-authorized");
        beam.kiss(rando);
        vm.expectRevert("RewardsBeam/not-authorized");
        beam.diss(rando);
        vm.expectRevert("RewardsBeam/not-authorized");
        beam.file("maxVestTot", 1);
        vm.stopPrank();
    }

    function testSetNotFacilitator() public {
        vm.prank(rando);
        vm.expectRevert("RewardsBeam/not-facilitator");
        beam.set(1 ether);
    }

    // --- file ---

    function testFile() public {
        vm.expectEmit(true, true, true, true);
        emit File("maxVestTot", 1);
        beam.file("maxVestTot", 1);
        assertEq(beam.maxVestTot(), 1);

        beam.file("vestTau", 30 days);
        assertEq(beam.vestTau(), 30 days);
        beam.file("tau", 7 days);
        assertEq(beam.tau(), 7 days);
        beam.file("toc", 8);
        assertEq(beam.toc(), 8);
    }

    function testFileBounds() public {
        vm.expectRevert("RewardsBeam/vestTau-zero");
        beam.file("vestTau", 0);
        beam.file("vestTau", 1 days);

        vm.expectRevert("RewardsBeam/invalid-tau-value");
        beam.file("tau", uint256(type(uint64).max) + 1);

        vm.expectRevert("RewardsBeam/invalid-toc-value");
        beam.file("toc", uint256(type(uint128).max) + 1);

        vm.expectRevert("RewardsBeam/file-unrecognized-param");
        beam.file("nope", 1);
    }

    // --- set: boundaries ---

    function testSetBoundaries() public {
        vm.startPrank(facilitator);

        vm.expectRevert("RewardsBeam/vestTot-zero");
        beam.set(0);

        vm.expectRevert("RewardsBeam/vestTot-above-max");
        beam.set(MAX_VEST_TOT + 1);

        vm.stopPrank();
    }

    function testSetRateAboveVestCap() public {
        // Governance can file a vestTau short enough that maxVestTot overshoots the vest-wide rate ceiling.
        uint256 cap = vest.cap();
        beam.file("vestTau", 1);
        beam.file("maxVestTot", cap + 1);
        vm.prank(facilitator);
        vm.expectRevert("RewardsBeam/rate-above-vest-cap");
        beam.set(cap + 1);
    }

    function testSetUsesGovernanceFiledVestTau() public {
        beam.file("vestTau", 30 days);
        vm.prank(facilitator);
        beam.set(20_000_000 ether);

        uint256 newId = dist.vestId();
        assertEq(vest.fin(newId) - vest.bgn(newId), 30 days);
    }

    function testFacilitatorCannotFileVestTau() public {
        vm.prank(facilitator);
        vm.expectRevert("RewardsBeam/not-authorized");
        beam.file("vestTau", 1 days);
    }

    function testSetRevertsWithoutVestAuth() public {
        RewardsBeam orphan = new RewardsBeam(address(dist));
        orphan.file("maxVestTot", MAX_VEST_TOT);
        orphan.file("tau", COOLDOWN);
        orphan.kiss(facilitator);

        vm.prank(facilitator);
        vm.expectRevert("DssVest/not-authorized");
        orphan.set(1_000_000 ether);
    }

    function testSetRevertsWhenDistVestIdUnset() public {
        vm.mockCall(address(dist), abi.encodeWithSignature("vestId()"), abi.encode(uint256(0)));
        vm.prank(facilitator);
        vm.expectRevert("RewardsBeam/dist-vest-id-not-set");
        beam.set(1_000_000 ether);
        vm.clearMockedCalls();
    }

    function testSetDoesNotRequireAllowanceToCoverTheWholeStream() public {
        // Leave just enough allowance for the outgoing flush and nothing more. `DssVest` draws `unpaid`
        // progressively, so creating a far larger stream is legitimate; governance tops up as it goes.
        uint256 pending = vest.unpaid(dist.vestId());
        vm.prank(pauseProxy);
        gem.approve(address(vest), pending);

        vm.prank(facilitator);
        beam.set(60_000_000 ether);

        assertEq(gem.allowance(pauseProxy, address(vest)), 0);
        assertEq(vest.tot(dist.vestId()), 60_000_000 ether);
    }

    function testSetRevertsWhenTreasuryCannotCoverTheFlush() public {
        // The flush moves real tokens, so an unfunded treasury stops `set()` without any explicit check.
        uint256 bal = gem.balanceOf(pauseProxy);
        vm.prank(pauseProxy);
        gem.transfer(rando, bal);

        vm.prank(facilitator);
        vm.expectRevert();
        beam.set(60_000_000 ether);
    }

    function testSetCooldown() public {
        vm.prank(facilitator);
        beam.set(60_000_000 ether);
        assertEq(beam.toc(), block.timestamp);

        vm.warp(block.timestamp + COOLDOWN - 1);
        vm.prank(facilitator);
        vm.expectRevert("RewardsBeam/too-early");
        beam.set(50_000_000 ether);

        vm.warp(block.timestamp + 1);
        vm.prank(facilitator);
        beam.set(50_000_000 ether);
    }

    // --- set: behaviour ---

    function testSetRollsStream() public {
        uint256 prevId = dist.vestId();
        uint256 pending = vest.unpaid(prevId);
        assertGt(pending, 0, "fixture expects a live stream with pending rewards");

        uint256 farmBalBefore = gem.balanceOf(address(farm));
        uint256 allowanceBefore = gem.allowance(pauseProxy, address(vest));
        uint256 newVestTot = 60_000_000 ether;

        vm.expectEmit(true, true, true, true);
        emit Set(prevId, prevId + 1, newVestTot, VEST_TAU);
        vm.prank(facilitator);
        beam.set(newVestTot);

        // Outgoing stream flushed then retired.
        assertEq(gem.balanceOf(address(farm)) - farmBalBefore, pending);
        assertEq(gem.allowance(pauseProxy, address(vest)), allowanceBefore - pending);
        assertEq(vest.fin(prevId), block.timestamp);
        assertEq(vest.tot(prevId), vest.rxd(prevId));
        assertFalse(vest.valid(prevId));

        // Replacement stream created, restricted and wired in.
        uint256 newId = dist.vestId();
        assertEq(newId, prevId + 1);
        assertEq(vest.usr(newId), address(dist));
        assertEq(vest.tot(newId), newVestTot);
        assertEq(vest.rxd(newId), 0);
        assertEq(vest.bgn(newId), block.timestamp);
        assertEq(vest.clf(newId), block.timestamp);
        assertEq(vest.fin(newId), block.timestamp + VEST_TAU);
        assertEq(vest.res(newId), 1);

        // The farm re-rated on the flush; rewardsDuration is untouched.
        assertEq(farm.periodFinish(), block.timestamp + farm.rewardsDuration());
        assertEq(farm.rewardsDuration(), 7 days);
    }

    function testSetPinsBgnToNowAndNeverFrontloads() public {
        uint256 farmBalBefore = gem.balanceOf(address(farm));
        uint256 pending = vest.unpaid(dist.vestId());

        vm.prank(facilitator);
        beam.set(60_000_000 ether);

        uint256 newId = dist.vestId();
        assertEq(vest.bgn(newId), block.timestamp);
        assertEq(vest.clf(newId), block.timestamp);
        assertEq(vest.unpaid(newId), 0);
        assertEq(vest.rxd(newId), 0);
        // The only SKY that moved is the outgoing stream's flush.
        assertEq(gem.balanceOf(address(farm)) - farmBalBefore, pending);
    }

    function testSetTwiceLowersTheEmissionRate() public {
        vm.prank(pauseProxy);
        gem.approve(address(vest), 200_000_000 ether);
        deal(address(gem), pauseProxy, 200_000_000 ether);

        vm.prank(facilitator);
        beam.set(90_000_000 ether);
        vm.warp(block.timestamp + COOLDOWN);
        uint256 rateBefore = farm.rewardRate();

        vm.prank(facilitator);
        beam.set(9_000_000 ether);
        vm.warp(block.timestamp + COOLDOWN);

        vm.prank(facilitator);
        beam.set(9_000_000 ether);
        assertLt(farm.rewardRate(), rateBefore);
    }

    function testSetFuzzBoundedParams(uint256 vestTot, uint256 vestTau) public {
        vm.prank(pauseProxy);
        gem.approve(address(vest), MAX_VEST_TOT * 2);

        vestTau = bound(vestTau, 7 days, 365 days);
        beam.file("vestTau", vestTau);

        uint256 rateCeil = vestTau * vest.cap();
        uint256 ceil = rateCeil < MAX_VEST_TOT ? rateCeil : MAX_VEST_TOT;
        vestTot = bound(vestTot, 1, ceil);

        uint256 prevId = dist.vestId();
        vm.prank(facilitator);
        beam.set(vestTot);

        uint256 newId = dist.vestId();
        assertEq(newId, prevId + 1);
        assertEq(vest.tot(newId), vestTot);
        assertEq(vest.bgn(newId), block.timestamp);
        // A stream that starts now can never frontload rewards into the farm.
        assertEq(vest.rxd(newId), 0);
    }
}
