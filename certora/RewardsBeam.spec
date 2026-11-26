// RewardsBeam.spec

using DssVestMock as vest;
using VestedRewardsDistributionMock as dist;

// --- Methods block ---

methods {
    // RewardsBeam
    function wards(address)      external returns (uint256) envfree;
    function buds(address)       external returns (uint256) envfree;
    function maxVestTot()        external returns (uint256) envfree;
    function vestTau()           external returns (uint256) envfree;
    function tau()               external returns (uint64)  envfree;
    function toc()               external returns (uint128) envfree;

    // DssVestMock
    function vest.wards(address) external returns (uint256) envfree;
    function vest.cap()          external returns (uint256) envfree;
    function vest.ids()          external returns (uint256) envfree;
    function vest.usr(uint256)   external returns (address) envfree;
    function vest.bgn(uint256)   external returns (uint256) envfree;
    function vest.clf(uint256)   external returns (uint256) envfree;
    function vest.fin(uint256)   external returns (uint256) envfree;
    function vest.mgr(uint256)   external returns (address) envfree;
    function vest.res(uint256)   external returns (uint256) envfree;
    function vest.tot(uint256)   external returns (uint256) envfree;
    function vest.rxd(uint256)   external returns (uint256) envfree;
    function vest.unpaidOf(uint256) external returns (uint256) envfree;

    // VestedRewardsDistributionMock
    function dist.wards(address) external returns (uint256) envfree;
    function dist.vestId()       external returns (uint256) envfree;
}

// --- Definitions ---

definition TWENTY_YEARS() returns mathint = 20 * 365 * 24 * 60 * 60;

// file() parameter names
definition MAX_VEST_TOT() returns bytes32 = to_bytes32(0x6d617856657374546f7400000000000000000000000000000000000000000000); // "maxVestTot"
definition VEST_TAU()     returns bytes32 = to_bytes32(0x7665737454617500000000000000000000000000000000000000000000000000); // "vestTau"
definition TAU()          returns bytes32 = to_bytes32(0x7461750000000000000000000000000000000000000000000000000000000000); // "tau"
definition TOC()          returns bytes32 = to_bytes32(0x746f630000000000000000000000000000000000000000000000000000000000); // "toc"

// --- Storage Affected Rule ---

// Verify that each storage slot is only modified in the corresponding functions
rule storageAffected(method f) filtered { f -> f.contract == currentContract && !f.isView } {
    env e;
    calldataarg args;

    address anyAddr;

    mathint wardsBefore      = wards(anyAddr);
    mathint budsBefore       = buds(anyAddr);
    mathint maxVestTotBefore = maxVestTot();
    mathint vestTauBefore    = vestTau();
    mathint tauBefore        = tau();
    mathint tocBefore        = toc();

    f(e, args);

    assert wards(anyAddr) != wardsBefore =>
        f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector;
    assert buds(anyAddr) != budsBefore =>
        f.selector == sig:kiss(address).selector || f.selector == sig:diss(address).selector;
    assert maxVestTot() != maxVestTotBefore => f.selector == sig:file(bytes32, uint256).selector;
    assert vestTau()    != vestTauBefore    => f.selector == sig:file(bytes32, uint256).selector;
    assert tau()        != tauBefore        => f.selector == sig:file(bytes32, uint256).selector;
    assert toc()        != tocBefore        =>
        f.selector == sig:file(bytes32, uint256).selector || f.selector == sig:set(uint256).selector;
}

// --- Admin functions: rely ---

rule rely(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    rely(e, usr);

    assert wards(usr) == 1;
    assert wards(other) == wardsOtherBefore;
}

rule rely_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2;
}

// --- Admin functions: deny ---

rule deny(address usr) {
    env e;

    address other;
    require other != usr;

    mathint wardsOtherBefore = wards(other);

    deny(e, usr);

    assert wards(usr) == 0;
    assert wards(other) == wardsOtherBefore;
}

rule deny_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2;
}

// --- Admin functions: kiss ---

rule kiss(address usr) {
    env e;

    address other;
    require other != usr;

    mathint budsOtherBefore = buds(other);

    kiss(e, usr);

    assert buds(usr) == 1;
    assert buds(other) == budsOtherBefore;
}

rule kiss_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    kiss@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2;
}

// --- Admin functions: diss ---

rule diss(address usr) {
    env e;

    address other;
    require other != usr;

    mathint budsOtherBefore = buds(other);

    diss(e, usr);

    assert buds(usr) == 0;
    assert buds(other) == budsOtherBefore;
}

rule diss_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    diss@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert lastReverted <=> revert1 || revert2;
}

// --- Admin functions: file ---

rule file_uint256(bytes32 what, uint256 data) {
    env e;

    mathint maxVestTotBefore = maxVestTot();
    mathint vestTauBefore    = vestTau();
    mathint tauBefore        = tau();
    mathint tocBefore        = toc();

    file(e, what, data);

    assert what == MAX_VEST_TOT() => maxVestTot() == data;
    assert what != MAX_VEST_TOT() => maxVestTot() == maxVestTotBefore;
    assert what == VEST_TAU()     => vestTau() == data;
    assert what != VEST_TAU()     => vestTau() == vestTauBefore;
    assert what == TAU()          => tau() == data;
    assert what != TAU()          => tau() == tauBefore;
    assert what == TOC()          => toc() == data;
    assert what != TOC()          => toc() == tocBefore;
}

rule file_uint256_revert(bytes32 what, uint256 data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != MAX_VEST_TOT() && what != VEST_TAU() && what != TAU() && what != TOC();
    bool revert4 = what == VEST_TAU() && (data == 0 || data > TWENTY_YEARS());
    bool revert5 = what == TAU() && data > max_uint64;
    bool revert6 = what == TOC() && data > max_uint128;

    assert lastReverted <=> revert1 || revert2 || revert3 || revert4 || revert5 || revert6;
}

// --- Facilitator functions: set ---

rule set(uint256 vestTot) {
    env e;

    require e.block.timestamp <= max_uint128;
    // State DssVest and VestedRewardsDistribution always keep: `dist` points at an award that `vest` created
    require dist.vestId() <= vest.ids();
    // DssVest bounds rxd + unpaid by tot, which fits in a uint128
    require vest.rxd(dist.vestId()) + vest.unpaidOf(dist.vestId()) <= max_uint128;

    uint256 prevId         = dist.vestId();
    mathint prevRxdBefore  = vest.rxd(prevId);
    mathint prevUnpaid     = vest.unpaidOf(prevId);
    mathint idsBefore      = vest.ids();

    set(e, vestTot);

    uint256 newId = dist.vestId();

    assert toc() == e.block.timestamp;
    // The outgoing stream is flushed (whatever it owed is paid out) and then retired
    assert vest.rxd(prevId) == prevRxdBefore + prevUnpaid;
    assert vest.unpaidOf(prevId) == 0;
    assert vest.fin(prevId) <= e.block.timestamp;
    // A new restricted stream, owned by `dist` and with no manager, replaces it
    assert newId == idsBefore + 1;
    assert vest.usr(newId) == dist;
    assert vest.tot(newId) == vestTot;
    assert vest.mgr(newId) == 0;
    assert vest.res(newId) == 1;
    // It begins now with no cliff, so nothing is claimable on creation, and it lasts vestTau
    assert vest.bgn(newId) == e.block.timestamp;
    assert vest.clf(newId) == e.block.timestamp;
    assert vest.fin(newId) == e.block.timestamp + vestTau();
}

rule set_revert(uint256 vestTot) {
    env e;

    // DssVest never creates award 0
    require vest.usr(0) == 0;

    require vest.wards(currentContract) == 1;
    require dist.wards(currentContract) == 1;

    mathint budsSender    = buds(e.msg.sender);
    mathint maxVestTot    = maxVestTot();
    mathint vestTau       = vestTau();
    mathint tau           = tau();
    mathint toc           = toc();

    uint256 prevId        = dist.vestId();
    address prevUsr       = vest.usr(prevId);
    mathint prevRes       = vest.res(prevId);
    mathint prevUnpaid    = vest.unpaidOf(prevId);
    mathint cap           = vest.cap();
    mathint ids           = vest.ids();

    set@withrevert(e, vestTot);

    bool revert1  = e.msg.value > 0;
    bool revert2  = budsSender != 1;
    bool revert3  = tau + toc > max_uint128;
    bool revert4  = e.block.timestamp < tau + toc;
    bool revert5  = vestTot > maxVestTot;
    // vest.unpaid(prevId): the outgoing award must exist
    bool revert6  = prevUsr == 0;
    // dist.distribute() (only when something is owed): a restricted award only pays out to its user
    bool revert7  = prevUnpaid > 0 && prevRes != 0 && prevUsr != dist;
    // vest.yank(prevId) and vest.create(...)
    bool revert8  = vestTot == 0;
    bool revert9  = e.block.timestamp < TWENTY_YEARS();
    bool revert10 = vestTau == 0;
    bool revert11 = vestTau != 0 && vestTot / vestTau > cap;
    bool revert12 = vestTau > TWENTY_YEARS();
    bool revert13 = ids == max_uint256;
    bool revert14 = e.block.timestamp + vestTau > max_uint48;
    bool revert15 = vestTot > max_uint128;

    assert lastReverted <=> revert1  || revert2  || revert3  ||
                            revert4  || revert5  || revert6  ||
                            revert7  || revert8  || revert9  ||
                            revert10 || revert11 || revert12 ||
                            revert13 || revert14 || revert15;
}
