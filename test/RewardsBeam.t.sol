// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.24;

import "dss-test/DssTest.sol";
import {RewardsBeam} from "../src/RewardsBeam.sol";
import {RewardsBeamMom} from "../src/RewardsBeamMom.sol";
import {RewardsBeamInstance} from "../deploy/RewardsBeamInstance.sol";
import {RewardsBeamDeploy} from "../deploy/RewardsBeamDeploy.sol";
import {RewardsBeamInit, RewardsBeamConfig} from "../deploy/RewardsBeamInit.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface ChiefLike {
    function hat() external view returns (address);
}

interface WardsLike {
    function wards(address) external view returns (uint256);
}

interface DssVestTransferrableLike {
    function ids() external view returns (uint256);
    function TWENTY_YEARS() external view returns (uint256);
    function rely(address) external;
    function cap() external view returns (uint256);
    function czar() external view returns (address);
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
    function distribute() external returns (uint256);
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

contract RewardsBeamTest is DssTest {
    ChainlogLike constant chainlog = ChainlogLike(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
    uint256 constant FORK_BLOCK = 25_920_000;

    DssVestTransferrableLike vest;
    DistLike dist;
    FarmLike farm;
    GemLike gem;
    address pauseProxy;
    RewardsBeam beam;
    RewardsBeamMom mom;

    address constant DEPLOYER = address(0xDE9);
    address facilitator = address(0xFAC1);
    address facilitator2 = address(0xFAC2);
    address rando = address(0xDEAD);

    uint256 constant MAX_VEST_TOT = 150_000_000 ether;
    uint256 constant VEST_TAU = 100 days;
    uint256 constant COOLDOWN = 7 days;

    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event Set(uint256 indexed prevVestId, uint256 indexed vestId, uint256 vestTot, uint256 vestTau);

    function setUp() public {
        string memory rpc = vm.envOr("ETH_RPC_URL", string(""));
        vm.createSelectFork(rpc, FORK_BLOCK);

        pauseProxy = chainlog.getAddress("MCD_PAUSE_PROXY");
        dist = DistLike(chainlog.getAddress("REWARDS_DIST_LSSKY_SKY"));
        vest = DssVestTransferrableLike(chainlog.getAddress("MCD_VEST_SKY_TREASURY"));
        farm = FarmLike(chainlog.getAddress("REWARDS_LSSKY_SKY"));
        gem = GemLike(chainlog.getAddress("SKY"));

        // Sanity: the wiring the beam assumes is the wiring that is actually deployed.
        assertEq(dist.dssVest(), address(vest));
        assertEq(dist.stakingRewards(), address(farm));
        assertEq(dist.gem(), address(gem));
        assertEq(vest.czar(), pauseProxy);
        assertEq(farm.rewardsDistribution(), address(dist));

        // Leave the treasury allowance as deployed; tests that need more set it themselves.
        RewardsBeamInstance memory instance = _deployAndInit(0);
        beam = RewardsBeam(instance.beam);
        mom  = RewardsBeamMom(instance.mom);

        // Let the test contract act as governance on the beam directly.
        vm.prank(pauseProxy); beam.rely(address(this));
    }

    // --- deployment ---

    function testConstructor() public {
        vm.expectEmit();
        emit Rely(address(this));
        RewardsBeam beam_ = new RewardsBeam(address(dist));

        assertEq(address(beam_.dist()), address(dist));
        assertEq(address(beam_.vest()), address(vest));
        assertEq(beam_.maxVestTot(), 0);
        assertEq(beam_.vestTau(), 0);
        assertEq(beam_.tau(), 0);
        assertEq(beam_.toc(), 0);
        assertEq(beam_.wards(address(this)), 1);
    }

    function _buds() internal view returns (address[] memory buds) {
        buds = new address[](2);
        buds[0] = facilitator;
        buds[1] = facilitator2;
    }

    function _cfg(uint256 allowance) internal view returns (RewardsBeamConfig memory) {
        return RewardsBeamConfig({
            dist:        address(dist),
            buds:        _buds(),
            maxVestTot:  MAX_VEST_TOT,
            vestTau:     VEST_TAU,
            tau:         COOLDOWN,
            allowance:   allowance,
            beamKey:     "REWARDS_BEAM_LSSKY_SKY",
            momKey:      "REWARDS_BEAM_LSSKY_SKY_MOM"
        });
    }

    function _deploy() internal returns (RewardsBeamInstance memory instance) {
        vm.startPrank(DEPLOYER);
        instance = RewardsBeamDeploy.deploy(DEPLOYER, pauseProxy, address(dist));
        vm.stopPrank();
    }

    function _deployAndInit(uint256 allowance) internal returns (RewardsBeamInstance memory instance) {
        instance = _deploy();
        assertEq(RewardsBeam(instance.beam).wards(DEPLOYER), 0);
        assertEq(RewardsBeam(instance.beam).wards(pauseProxy), 1);
        assertEq(RewardsBeamMom(instance.mom).owner(), pauseProxy);

        vm.startPrank(pauseProxy);
        RewardsBeamInit.init(instance, _cfg(allowance));
        vm.stopPrank();

        RewardsBeam    beam_ = RewardsBeam(instance.beam);
        RewardsBeamMom mom_  = RewardsBeamMom(instance.mom);

        // Beam
        assertEq(WardsLike(address(vest)).wards(address(beam_)), 1);
        assertEq(WardsLike(address(dist)).wards(address(beam_)), 1);
        assertEq(beam_.maxVestTot(), MAX_VEST_TOT);
        assertEq(beam_.vestTau(), VEST_TAU);
        assertEq(beam_.tau(), COOLDOWN);
        assertEq(beam_.buds(facilitator), 1);
        assertEq(beam_.buds(facilitator2), 1);
        assertEq(chainlog.getAddress("REWARDS_BEAM_LSSKY_SKY"), address(beam_));

        // Mom
        assertEq(address(mom_.beam()), address(beam_));
        assertEq(address(mom_.dist()), address(dist));
        assertEq(address(mom_.vest()), address(vest));
        assertEq(mom_.authority(), chainlog.getAddress("MCD_ADM"));
        assertEq(beam_.wards(address(mom_)), 1);
        assertEq(WardsLike(address(vest)).wards(address(mom_)), 1);
        assertEq(chainlog.getAddress("REWARDS_BEAM_LSSKY_SKY_MOM"), address(mom_));
    }

    function testDeployAndInit() public {
        RewardsBeamInstance memory instance = _deployAndInit(300_000_000 ether);
        assertEq(gem.allowance(pauseProxy, address(vest)), 300_000_000 ether);

        // The initialized beam is live.
        vm.prank(facilitator);
        RewardsBeam(instance.beam).set(10_000_000 ether);
        assertEq(vest.tot(dist.vestId()), 10_000_000 ether);
    }

    function testDeployAndInitZeroAllowanceLeavesItUntouched() public {
        uint256 allowanceBefore = gem.allowance(pauseProxy, address(vest));
        _deployAndInit(0);
        assertEq(gem.allowance(pauseProxy, address(vest)), allowanceBefore);
    }

    function testDeployAndInitMaxAllowance() public {
        _deployAndInit(type(uint256).max);
        assertEq(gem.allowance(pauseProxy, address(vest)), type(uint256).max);
    }

    function init(RewardsBeamInstance memory instance, RewardsBeamConfig memory cfg) external {
        vm.startPrank(pauseProxy);
        RewardsBeamInit.init(instance, cfg);
        vm.stopPrank();
    }

    function testInitRevertsWhenTocNotZero() public {
        RewardsBeamInstance memory instance = _deploy();
        vm.prank(pauseProxy); RewardsBeam(instance.beam).file("toc", 1);

        vm.expectRevert("RewardsBeamInit/toc-not-zero");
        this.init(instance, _cfg(0));
    }

    function testInitRevertsOnDistMismatch() public {
        RewardsBeamInstance memory instance = _deploy();
        RewardsBeamConfig memory cfg = _cfg(0);
        cfg.dist = chainlog.getAddress("REWARDS_DIST_USDS_SKY");

        vm.expectRevert("RewardsBeamInit/dist-mismatch");
        this.init(instance, cfg);
    }

    function testInitRevertsWhenDistVestIdUnset() public {
        RewardsBeamInstance memory instance = _deploy();

        vm.mockCall(address(dist), abi.encodeWithSignature("vestId()"), abi.encode(uint256(0)));
        vm.expectRevert("RewardsBeamInit/dist-vest-id-not-set");
        this.init(instance, _cfg(0));
    }

    function testInitRevertsOnMomBeamMismatch() public {
        RewardsBeamInstance memory instance = _deploy();
        // A mom deployed for a different beam.
        instance.mom = _deploy().mom;

        vm.expectRevert("RewardsBeamInit/mom-beam-mismatch");
        this.init(instance, _cfg(0));
    }

    function testInitRevertsOnVestCzarMismatch() public {
        RewardsBeamInstance memory instance = _deploy();

        // Pretend the vest pulls from a treasury other than the pause proxy.
        vm.mockCall(address(vest), abi.encodeWithSignature("czar()"), abi.encode(rando));
        vm.expectRevert("RewardsBeamInit/vest-czar-mismatch");
        this.init(instance, _cfg(1));
    }

    function testFreshBeamIsInert() public {
        RewardsBeam fresh = new RewardsBeam(address(dist));
        assertEq(fresh.maxVestTot(), 0);
        assertEq(fresh.vestTau(), 0);
        assertEq(fresh.tau(), 0);
        assertEq(fresh.toc(), 0);

        fresh.kiss(facilitator);
        vm.prank(facilitator);
        vm.expectRevert("RewardsBeam/vestTot-above-max");
        fresh.set(1 ether);
    }

    // --- administration ---

    function testAuth() public {
        checkAuth(address(beam), "RewardsBeam");
    }

    function testModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](2);
        authedMethods[0] = beam.kiss.selector;
        authedMethods[1] = beam.diss.selector;

        vm.startPrank(address(0xBEEF));
        checkModifier(address(beam), "RewardsBeam/not-authorized", authedMethods);
        vm.stopPrank();
    }

    function testKissDiss() public {
        vm.expectEmit();
        emit Kiss(rando);
        beam.kiss(rando);
        assertEq(beam.buds(rando), 1);
        vm.expectEmit();
        emit Diss(rando);
        beam.diss(rando);
        assertEq(beam.buds(rando), 0);
    }

    function testSetNotFacilitator() public {
        vm.prank(rando);
        vm.expectRevert("RewardsBeam/not-facilitator");
        beam.set(1 ether);
    }

    // --- file ---

    function testFile() public {
        checkFileUint(address(beam), "RewardsBeam", ["maxVestTot", "vestTau", "tau", "toc"]);
    }

    function testFileBounds() public {
        uint256 twentyYears = vest.TWENTY_YEARS();
        vm.expectRevert("RewardsBeam/vestTau-out-of-boundaries");
        beam.file("vestTau", 0);
        vm.expectRevert("RewardsBeam/vestTau-out-of-boundaries");
        beam.file("vestTau", twentyYears + 1);
        beam.file("vestTau", 1);
        assertEq(beam.vestTau(), 1);
        beam.file("vestTau", twentyYears);
        assertEq(beam.vestTau(), twentyYears);

        vm.expectRevert("RewardsBeam/invalid-tau-value");
        beam.file("tau", uint256(type(uint64).max) + 1);
        beam.file("tau", uint256(type(uint64).max));
        assertEq(beam.tau(), type(uint64).max);

        vm.expectRevert("RewardsBeam/invalid-toc-value");
        beam.file("toc", uint256(type(uint128).max) + 1);
        beam.file("toc", uint256(type(uint128).max));
        assertEq(beam.toc(), type(uint128).max);

        vm.expectRevert("RewardsBeam/file-unrecognized-param");
        beam.file("random", 1);
    }

    // --- set: boundaries ---

    function testSetBoundaries() public {
        vm.startPrank(facilitator);

        vm.expectRevert("DssVest/no-vest-total-amount");
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
        vm.expectRevert("DssVest/rate-too-high");
        beam.set(cap + 1);
    }

    function testSetUsesGovernanceFiledVestTau() public {
        beam.file("vestTau", 30 days);
        vm.prank(facilitator);
        beam.set(20_000_000 ether);

        uint256 newId = dist.vestId();
        assertEq(vest.fin(newId) - vest.bgn(newId), 30 days);
    }

    function testSetRevertsWhenDistVestIdUnset() public {
        vm.mockCall(address(dist), abi.encodeWithSignature("vestId()"), abi.encode(uint256(0)));
        vm.prank(facilitator);
        vm.expectRevert("DssVest/invalid-award");
        beam.set(1_000_000 ether);
        vm.clearMockedCalls();
    }

    function testSetDoesNotRequireAllowanceToCoverTheWholeStream() public {
        // Leave just enough allowance for the outgoing flush and nothing more. `DssVest` draws `unpaid`
        // progressively, so creating a far larger stream is legitimate; governance tops up as it goes.
        uint256 pending = vest.unpaid(dist.vestId());
        vm.prank(pauseProxy); gem.approve(address(vest), pending);

        vm.prank(facilitator);
        beam.set(60_000_000 ether);

        assertEq(gem.allowance(pauseProxy, address(vest)), 0);
        assertEq(vest.tot(dist.vestId()), 60_000_000 ether);
    }

    function testSetRevertsWhenTreasuryCannotCoverTheFlush() public {
        // The flush moves real tokens, so an unfunded treasury stops `set()` without any explicit check.
        uint256 bal = gem.balanceOf(pauseProxy);
        vm.prank(pauseProxy); gem.transfer(rando, bal);

        vm.prank(facilitator);
        vm.expectRevert("Sky/insufficient-balance");
        beam.set(60_000_000 ether);
    }

    function testSetRevertsWhenAllowanceCannotCoverTheFlush() public {
        // The token caps cumulative transfers at the allowance, so the flush fails one wei short.
        uint256 pending = vest.unpaid(dist.vestId());
        vm.prank(pauseProxy); gem.approve(address(vest), pending - 1);

        vm.prank(facilitator);
        vm.expectRevert("Sky/insufficient-allowance");
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

        uint256 newId = vest.ids() + 1;

        vm.expectEmit();
        emit Set(prevId, newId, newVestTot, VEST_TAU);
        vm.prank(facilitator);
        beam.set(newVestTot);

        // Outgoing stream flushed then retired.
        assertEq(gem.balanceOf(address(farm)), farmBalBefore + pending);
        assertEq(gem.allowance(pauseProxy, address(vest)), allowanceBefore - pending);
        assertEq(vest.fin(prevId), block.timestamp);
        assertEq(vest.tot(prevId), vest.rxd(prevId));
        assertFalse(vest.valid(prevId));

        // Replacement stream created, restricted and wired in.
        assertEq(dist.vestId(), newId);
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

    function testSetSkipsFlushWhenNothingIsUnpaid() public {
        dist.distribute();
        uint256 prevId = dist.vestId();
        assertEq(vest.unpaid(prevId), 0);
        uint256 farmBalBefore = gem.balanceOf(address(farm));
        uint256 periodFinishBefore = farm.periodFinish();

        vm.prank(facilitator);
        beam.set(60_000_000 ether);

        // No flush: nothing moved and the farm was not re-notified, yet the rollover went through.
        assertEq(gem.balanceOf(address(farm)), farmBalBefore);
        assertEq(farm.periodFinish(), periodFinishBefore);
        assertFalse(vest.valid(prevId));
        assertEq(vest.tot(dist.vestId()), 60_000_000 ether);
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
        assertEq(gem.balanceOf(address(farm)), farmBalBefore + pending);
    }

    function testSetLowersTheEmissionRate() public {
        vm.prank(pauseProxy); gem.approve(address(vest), 200_000_000 ether);
        deal(address(gem), pauseProxy, 200_000_000 ether);

        vm.prank(facilitator);
        beam.set(90_000_000 ether);
        vm.warp(block.timestamp + 7 days);
        dist.distribute();
        assertApproxEqAbs(farm.rewardRate(), 90_000_000 ether / VEST_TAU, 1e6);

        vm.prank(facilitator);
        beam.set(9_000_000 ether);
        vm.warp(block.timestamp + 7 days);
        dist.distribute();
        assertApproxEqAbs(farm.rewardRate(), 9_000_000 ether / VEST_TAU, 1e6);
    }

    function testSetFuzzBoundedParams(uint256 vestTot, uint256 vestTau) public {
        vm.prank(pauseProxy); gem.approve(address(vest), MAX_VEST_TOT * 2);

        vestTau = bound(vestTau, 7 days, 365 days);
        beam.file("vestTau", vestTau);

        uint256 rateCeil = vestTau * vest.cap();
        uint256 ceil = rateCeil < MAX_VEST_TOT ? rateCeil : MAX_VEST_TOT;
        vestTot = bound(vestTot, 1, ceil);

        uint256 prevId = dist.vestId();
        vm.prank(facilitator);
        beam.set(vestTot);

        uint256 newId = dist.vestId();
        assertGt(newId, prevId);
        assertEq(vest.tot(newId), vestTot);
        assertEq(vest.bgn(newId), block.timestamp);
        // A stream that starts now can never frontload rewards into the farm.
        assertEq(vest.rxd(newId), 0);
    }

    // --- mom ---

    event SetOwner(address indexed newOwner);
    event SetAuthority(address indexed newAuthority);
    event Stop(uint256 vestId);

    function testMomConstructor() public {
        vm.expectEmit();
        emit SetOwner(address(this));
        RewardsBeamMom mom_ = new RewardsBeamMom(address(beam));
        assertEq(address(mom_.beam()), address(beam));
        assertEq(address(mom_.dist()), address(dist));
        assertEq(address(mom_.vest()), address(vest));
        assertEq(mom_.owner(),         address(this));
        assertEq(mom_.authority(),     address(0));
    }

    function testMomSetOwnerAndAuthority() public {
        vm.startPrank(rando);
        vm.expectRevert("RewardsBeamMom/not-owner");
        mom.setOwner(rando);
        vm.expectRevert("RewardsBeamMom/not-owner");
        mom.setAuthority(rando);
        vm.stopPrank();

        vm.startPrank(pauseProxy);
        vm.expectEmit(address(mom));
        emit SetAuthority(rando);
        mom.setAuthority(rando);
        assertEq(mom.authority(), rando);
        vm.expectEmit(address(mom));
        emit SetOwner(rando);
        mom.setOwner(rando);
        assertEq(mom.owner(), rando);
        vm.stopPrank();
    }

    function testMomStopNotAuthorized() public {
        checkModifier(address(mom), "RewardsBeamMom/not-authorized", [RewardsBeamMom.stop.selector]);

        vm.prank(address(pauseProxy));
        mom.setAuthority(address(0));
        checkModifier(address(mom), "RewardsBeamMom/not-authorized", [RewardsBeamMom.stop.selector]);
    }

    function testMomStopByOwner() public {
        vm.prank(pauseProxy);
        mom.stop();

        assertEq(beam.tau(), type(uint64).max);
        assertEq(vest.fin(dist.vestId()), block.timestamp);
    }

    function testMomStopByHat() public {
        uint256 vestId = dist.vestId();
        assertGt(vest.fin(vestId), block.timestamp);

        vm.expectEmit(address(mom));
        emit Stop(vestId);
        vm.prank(ChiefLike(chainlog.getAddress("MCD_ADM")).hat());
        mom.stop();

        // The beam is disabled and the running stream ends now.
        assertEq(beam.tau(), type(uint64).max);
        assertEq(vest.fin(vestId), block.timestamp);

        // No facilitator can start a new stream afterwards, however long they wait.
        vm.warp(block.timestamp + 100 * 365 days);
        vm.prank(facilitator);
        vm.expectRevert("RewardsBeam/too-early");
        beam.set(1);
    }

    function testMomStopKeepsAccruedClaimable() public {
        uint256 vestId = dist.vestId();
        uint256 pending = vest.unpaid(vestId);
        assertGt(pending, 0, "fixture expects a live stream with pending rewards");
        uint256 farmBalBefore = gem.balanceOf(address(farm));

        vm.prank(pauseProxy);
        mom.stop();

        // What accrued before the stop still reaches the farm, and nothing accrues after it.
        vm.warp(block.timestamp + 7 days);
        assertEq(vest.unpaid(vestId), pending);
        dist.distribute();
        assertEq(gem.balanceOf(address(farm)), farmBalBefore + pending);
        assertEq(vest.unpaid(vestId), 0);
    }

    function testMomStopWithoutVestId() public {
        vm.mockCall(address(dist), abi.encodeWithSignature("vestId()"), abi.encode(uint256(0)));

        // There is no stream to yank, but the beam is still disabled.
        vm.expectEmit(address(mom));
        emit Stop(0);
        vm.prank(pauseProxy);
        mom.stop();
        vm.clearMockedCalls();

        assertEq(beam.tau(), type(uint64).max);
    }
}
