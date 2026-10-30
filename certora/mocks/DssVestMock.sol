// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

// Models the parts of DssVest that RewardsBeam relies on, keeping DssVest's revert conditions for
// `create`, `restrict`, `yank` and `vest`. DssVest itself is verified in its own repository; this mock
// abstracts two things away:
// - accrual: `unpaid` is a free storage value instead of the linear `tot * (t - bgn) / (fin - bgn) - rxd`;
// - payment: `vest` updates the accounting but moves no tokens (the treasury pull of DssVestTransferrable).
contract DssVestMock {
    uint256 public constant TWENTY_YEARS = 20 * 365 days;

    mapping (address => uint256) public wards;
    uint256 public cap;
    uint256 public ids;

    mapping (uint256 => address) public usr;
    mapping (uint256 => uint256) public bgn;
    mapping (uint256 => uint256) public clf;
    mapping (uint256 => uint256) public fin;
    mapping (uint256 => address) public mgr;
    mapping (uint256 => uint256) public res;
    mapping (uint256 => uint256) public tot;
    mapping (uint256 => uint256) public rxd;
    mapping (uint256 => uint256) public unpaidOf;

    function unpaid(uint256 _id) external view returns (uint256) {
        require(usr[_id] != address(0), "DssVest/invalid-award");
        return unpaidOf[_id];
    }

    function create(address _usr, uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _eta, address _mgr) external returns (uint256 id) {
        require(wards[msg.sender] == 1,                    "DssVest/not-authorized");
        require(_usr != address(0),                        "DssVest/invalid-user");
        require(_tot > 0,                                  "DssVest/no-vest-total-amount");
        require(_bgn < block.timestamp + TWENTY_YEARS,     "DssVest/bgn-too-far");
        require(_bgn > block.timestamp - TWENTY_YEARS,     "DssVest/bgn-too-long-ago");
        require(_tau > 0,                                  "DssVest/tau-zero");
        require(_tot / _tau <= cap,                        "DssVest/rate-too-high");
        require(_tau <= TWENTY_YEARS,                      "DssVest/tau-too-long");
        require(_eta <= _tau,                              "DssVest/eta-too-long");
        require(ids < type(uint256).max,                   "DssVest/ids-overflow");
        // DssVest stores bgn, clf and fin as uint48 and tot as uint128
        require(_bgn + _tau <= type(uint48).max,           "DssVest/uint48-overflow");
        require(_tot <= type(uint128).max,                 "DssVest/uint128-overflow");

        id = ++ids;
        usr[id]      = _usr;
        bgn[id]      = _bgn;
        clf[id]      = _bgn + _eta;
        fin[id]      = _bgn + _tau;
        mgr[id]      = _mgr;
        res[id]      = 0;
        tot[id]      = _tot;
        rxd[id]      = 0;
        unpaidOf[id] = 0;
    }

    function restrict(uint256 _id) external {
        require(usr[_id] != address(0),                                  "DssVest/invalid-award");
        require(wards[msg.sender] == 1 || usr[_id] == msg.sender,        "DssVest/not-authorized");
        res[_id] = 1;
    }

    function yank(uint256 _id) external {
        require(wards[msg.sender] == 1 || mgr[_id] == msg.sender,        "DssVest/not-authorized");
        require(usr[_id] != address(0),                                  "DssVest/invalid-award");
        if (block.timestamp < fin[_id]) {
            fin[_id] = block.timestamp;
            // DssVest bounds these by `tot`, which fits in a uint128
            unchecked { tot[_id] = rxd[_id] + unpaidOf[_id]; }
        }
    }

    function vest(uint256 _id, uint256 _maxAmt) external {
        require(usr[_id] != address(0),                                  "DssVest/invalid-award");
        require(res[_id] == 0 || usr[_id] == msg.sender,                 "DssVest/only-user-can-claim");
        uint256 amt = unpaidOf[_id] < _maxAmt ? unpaidOf[_id] : _maxAmt;
        // DssVest bounds these by `tot`, which fits in a uint128
        unchecked {
            unpaidOf[_id] -= amt;
            rxd[_id]      += amt;
        }
    }
}
