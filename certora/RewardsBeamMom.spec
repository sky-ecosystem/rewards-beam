// RewardsBeamMom.spec

using RewardsBeam as beam;
using DssVestMock as vest;
using VestedRewardsDistributionMock as dist;

// --- Methods block ---

methods {
    // RewardsBeamMom storage getters
    function owner()     external returns (address) envfree;
    function authority() external returns (address) envfree;

    // RewardsBeamMom immutable getters
    function beam() external returns (address) envfree;
    function dist() external returns (address) envfree;
    function vest() external returns (address) envfree;

    // RewardsBeam functions reached through RewardsBeamMom.stop
    function beam.wards(address) external returns (uint256) envfree;
    function beam.buds(address)  external returns (uint256) envfree;
    function beam.maxVestTot()   external returns (uint256) envfree;
    function beam.vestTau()      external returns (uint256) envfree;
    function beam.tau()          external returns (uint64)  envfree;
    function beam.toc()          external returns (uint128) envfree;

    // DssVestMock functions reached through RewardsBeamMom.stop
    function vest.wards(address)    external returns (uint256) envfree;
    function vest.usr(uint256)      external returns (address) envfree;
    function vest.fin(uint256)      external returns (uint256) envfree;
    function vest.mgr(uint256)      external returns (address) envfree;
    function vest.tot(uint256)      external returns (uint256) envfree;
    function vest.rxd(uint256)      external returns (uint256) envfree;
    function vest.unpaidOf(uint256) external returns (uint256) envfree;

    // VestedRewardsDistributionMock functions reached through RewardsBeamMom.stop
    function dist.vestId() external returns (uint256) envfree;

    // The authority is not part of the scene, its answer is modelled by a ghost so that
    // both the `authority == 0` and the `authority != 0` branches stay reachable
    function _.canCall(address src, address dst, bytes4 sig_) external => canCallGhost(src, dst, sig_) expect bool;
}

ghost canCallGhost(address, address, bytes4) returns bool;

// --- Storage Affected Rule ---

rule storageAffected(method f) filtered { f -> !f.isView } {
    env e;
    calldataarg args;

    address ownerBefore     = owner();
    address authorityBefore = authority();

    f(e, args);

    address ownerAfter     = owner();
    address authorityAfter = authority();

    assert ownerAfter != ownerBefore =>
        f.selector == sig:setOwner(address).selector;
    assert authorityAfter != authorityBefore =>
        f.selector == sig:setAuthority(address).selector;
}

// --- Admin functions: setOwner ---

rule setOwner(address owner_) {
    env e;

    setOwner(e, owner_);

    assert owner() == owner_;
}

rule setOwner_revert(address owner_) {
    env e;

    address ownerBefore = owner();

    setOwner@withrevert(e, owner_);

    bool revert1 = e.msg.value > 0;
    bool revert2 = e.msg.sender != ownerBefore;

    assert lastReverted <=> revert1 || revert2;
}

// --- Admin functions: setAuthority ---

rule setAuthority(address authority_) {
    env e;

    setAuthority(e, authority_);

    assert authority() == authority_;
}

rule setAuthority_revert(address authority_) {
    env e;

    address ownerBefore = owner();

    setAuthority@withrevert(e, authority_);

    bool revert1 = e.msg.value > 0;
    bool revert2 = e.msg.sender != ownerBefore;

    assert lastReverted <=> revert1 || revert2;
}

// --- Emergency functions: stop ---

rule stop() {
    env e;

    // DssVest bounds rxd + unpaid by tot, which fits in a uint128
    require vest.rxd(dist.vestId()) + vest.unpaidOf(dist.vestId()) <= max_uint128;

    address anyAddr;
    uint256 otherId;
    require otherId != dist.vestId();

    uint256 vestId = dist.vestId();

    mathint beamWardsBefore      = beam.wards(anyAddr);
    mathint beamBudsBefore       = beam.buds(anyAddr);
    mathint beamMaxVestTotBefore = beam.maxVestTot();
    mathint beamVestTauBefore    = beam.vestTau();
    mathint beamTocBefore        = beam.toc();

    mathint finBefore      = vest.fin(vestId);
    mathint totBefore      = vest.tot(vestId);
    mathint rxdBefore      = vest.rxd(vestId);
    mathint unpaidBefore   = vest.unpaidOf(vestId);
    mathint otherFinBefore = vest.fin(otherId);
    mathint otherTotBefore = vest.tot(otherId);

    stop(e);

    // The beam is disabled through an unreachable cooldown, every other knob is left as it was
    assert beam.tau() == max_uint64;
    assert beam.wards(anyAddr) == beamWardsBefore;
    assert beam.buds(anyAddr)  == beamBudsBefore;
    assert beam.maxVestTot()   == beamMaxVestTotBefore;
    assert beam.vestTau()      == beamVestTauBefore;
    assert beam.toc()          == beamTocBefore;

    // The distribution contract keeps pointing at the same stream
    assert dist.vestId() == vestId;

    // The current stream, if any, ends now and keeps only what has accrued so far claimable
    assert vestId != 0 && finBefore > e.block.timestamp => vest.fin(vestId) == e.block.timestamp;
    assert vestId != 0 && finBefore > e.block.timestamp => vest.tot(vestId) == rxdBefore + unpaidBefore;
    assert vestId == 0 || finBefore <= e.block.timestamp => vest.fin(vestId) == finBefore;
    assert vestId == 0 || finBefore <= e.block.timestamp => vest.tot(vestId) == totBefore;
    assert vest.rxd(vestId)      == rxdBefore;
    assert vest.unpaidOf(vestId) == unpaidBefore;

    // Other streams are untouched
    assert vest.fin(otherId) == otherFinBefore;
    assert vest.tot(otherId) == otherTotBefore;
}

rule stop_revert() {
    env e;

    address owner     = owner();
    address authority = authority();
    bool    canCall   = canCallGhost(e.msg.sender, currentContract, to_bytes4(sig:stop().selector));

    require beam.wards(currentContract) == 1 && vest.wards(currentContract) == 1;

    // DssVest.yank(vestId) needs RewardsBeamMom as a ward or as the award's manager, and the award to exist
    uint256 vestId    = dist.vestId();
    address vestMgr   = vest.mgr(vestId);
    address vestUsr   = vest.usr(vestId);

    require vestMgr == currentContract && vestUsr != 0;

    stop@withrevert(e);

    bool revert1 = e.msg.value > 0;
    // isAuthorized: the owner always passes, anyone else needs a non-zero authority that allows it
    bool revert2 = e.msg.sender != owner && (authority == 0 || !canCall);

    assert lastReverted <=> revert1 || revert2;
}
