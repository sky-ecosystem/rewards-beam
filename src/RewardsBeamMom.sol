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

interface AuthorityLike {
    function canCall(address src, address dst, bytes4 sig) external view returns (bool);
}

interface RewardsBeamLike {
    function dist() external view returns (address);
    function vest() external view returns (address);
    function file(bytes32, uint256) external;
}

interface VestedRewardsDistributionLike {
    function vestId() external view returns (uint256);
}

interface DssVestLike {
    function yank(uint256) external;
}

// Bypass governance delay to stop the beam and the stream it manages
contract RewardsBeamMom {

    // --- Storage variables ---

    address public owner;
    address public authority;

    // --- Immutables ---

    RewardsBeamLike               public immutable beam;
    VestedRewardsDistributionLike public immutable dist;
    DssVestLike                   public immutable vest;

    // --- Events ---

    event SetOwner(address indexed newOwner);
    event SetAuthority(address indexed newAuthority);
    event Stop(uint256 vestId);

    // --- Modifiers ---

    modifier onlyOwner() {
        require(msg.sender == owner, "RewardsBeamMom/not-owner");
        _;
    }

    modifier auth() {
        require(isAuthorized(msg.sender, msg.sig), "RewardsBeamMom/not-authorized");
        _;
    }

    // --- Constructor ---

    constructor(address beam_) {
        beam = RewardsBeamLike(beam_);
        dist = VestedRewardsDistributionLike(beam.dist());
        vest = DssVestLike(beam.vest());

        owner = msg.sender;
        emit SetOwner(msg.sender);
    }

    // --- Internal functions ---

    function isAuthorized(address src, bytes4 sig) internal view returns (bool) {
        if (src == owner) {
            return true;
        } else if (authority != address(0)) {
            return AuthorityLike(authority).canCall(src, address(this), sig);
        }
        return false;
    }

    // --- Admin functions ---

    function setOwner(address owner_) external onlyOwner {
        owner = owner_;
        emit SetOwner(owner_);
    }

    function setAuthority(address authority_) external onlyOwner {
        authority = authority_;
        emit SetAuthority(authority_);
    }

    // --- Emergency functions ---

    // Disables the beam, so no facilitator can start a new stream, and yanks the current one.
    // The yank keeps what has accrued so far claimable, so the farm still receives it on the next distribution.
    // Repeated calls do not revert: yanking a stream that already ended is a no-op.
    function stop() external auth {
        beam.file("maxVestTot", 0);

        uint256 vestId = dist.vestId();
        if (vestId != 0) {
            vest.yank(vestId);
        }

        emit Stop(vestId);
    }
}
