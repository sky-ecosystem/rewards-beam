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

pragma solidity >=0.8.0;

interface ChainlogLike {
    function setAddress(bytes32, address) external;
}

interface RewardsBeamLike {
    function dist() external view returns (address);
    function file(bytes32, uint256) external;
    function kiss(address) external;
}

interface VestedRewardsDistributionLike {
    function dssVest() external view returns (address);
    function gem() external view returns (address);
    function rely(address) external;
}

interface DssVestLike {
    function rely(address) external;
}

interface GemLike {
    function approve(address, uint256) external;
}

struct RewardsBeamConfig {
    address   dist;
    address[] buds;      // Facilitators allowed to call `set()`
    uint256   maxVestTot;
    uint256   vestTau;
    uint256   tau;
    uint256   allowance; // [wad] Treasury's gem allowance to a transferrable vest; 0 to skip
    bytes32   key;
}

library RewardsBeamInit {

    ChainlogLike constant internal chainlog = ChainlogLike(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    function init(
        address                  beam_,
        RewardsBeamConfig memory cfg
    ) internal {
        RewardsBeamLike               beam = RewardsBeamLike(beam_);
        VestedRewardsDistributionLike dist = VestedRewardsDistributionLike(cfg.dist);
        DssVestLike                   vest = DssVestLike(dist.dssVest());

        // --- Sanity checks ---

        require(beam.dist() == address(dist), "RewardsBeamInit/dist-mismatch");

        // --- Set permissions ---

        // Rely the beam on vest to create, restrict and yank streams
        vest.rely(address(beam));
        // Rely the beam on dist to file the new vestId
        dist.rely(address(beam));

        // --- Treasury allowance ---

        if (cfg.allowance > 0) {
            // It assumes vest.czar() == address(this) (pauseProxy)
            GemLike(dist.gem()).approve(address(vest), cfg.allowance);
        }

        // --- Configure the beam ---

        beam.file("maxVestTot", cfg.maxVestTot);
        beam.file("vestTau",    cfg.vestTau);
        beam.file("tau",        cfg.tau);
        for (uint256 i; i < cfg.buds.length; i++) {
            beam.kiss(cfg.buds[i]);
        }

        // --- Chainlog ---

        chainlog.setAddress(cfg.key, address(beam));
    }
}
