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

import { RewardsBeamInstance } from "./RewardsBeamInstance.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
    function setAddress(bytes32, address) external;
}

interface RewardsBeamLike {
    function dist() external view returns (address);
    function toc() external view returns (uint128);
    function file(bytes32, uint256) external;
    function kiss(address) external;
    function rely(address) external;
}

interface RewardsBeamMomLike {
    function beam() external view returns (address);
    function setAuthority(address) external;
}

interface VestedRewardsDistributionLike {
    function dssVest() external view returns (address);
    function gem() external view returns (address);
    function vestId() external view returns (uint256);
    function rely(address) external;
}

interface DssVestLike {
    function czar() external view returns (address);
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
    uint256   allowance; // [token decimals precision] Treasury's gem allowance to a transferrable vest; 0 to skip
    bytes32   beamKey;
    bytes32   momKey;
}

library RewardsBeamInit {

    ChainlogLike constant internal chainlog = ChainlogLike(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    function init(
        RewardsBeamInstance memory instance,
        RewardsBeamConfig   memory cfg
    ) internal {
        RewardsBeamLike               beam = RewardsBeamLike(instance.beam);
        RewardsBeamMomLike            mom  = RewardsBeamMomLike(instance.mom);
        VestedRewardsDistributionLike dist = VestedRewardsDistributionLike(cfg.dist);
        DssVestLike                   vest = DssVestLike(dist.dssVest());

        // --- Sanity checks ---

        require(beam.toc() == 0,              "RewardsBeamInit/toc-not-zero");
        require(beam.dist() == address(dist), "RewardsBeamInit/dist-mismatch");
        require(dist.vestId() != 0,           "RewardsBeamInit/dist-vest-id-not-set");
        require(mom.beam() == address(beam),  "RewardsBeamInit/mom-beam-mismatch");

        // --- Set permissions ---

        // Rely the beam on vest to create, restrict and yank streams
        vest.rely(address(beam));
        // Rely the beam on dist to file the new vestId
        dist.rely(address(beam));
        // Rely the mom on the beam to file vestTau to type(uint64).max)
        beam.rely(address(mom));
        // Rely the mom on vest to yank the current stream
        vest.rely(address(mom));

        // --- Treasury allowance ---

        // It assumes, that excepting a rare case, a DssVestTransferrable is being used, then allowance is needed.
        // Also, that the value here will cover all future beam creation/changes (along with the other streams)
        // or otherwise will be adjusted separately later.
        if (cfg.allowance > 0) {
            require(vest.czar() == chainlog.getAddress("MCD_PAUSE_PROXY"), "RewardsBeamInit/vest-czar-mismatch");
            GemLike(dist.gem()).approve(address(vest), cfg.allowance);
        }

        // --- Configure the beam ---

        beam.file("maxVestTot", cfg.maxVestTot);
        beam.file("vestTau",    cfg.vestTau);
        beam.file("tau",        cfg.tau);
        for (uint256 i; i < cfg.buds.length; i++) {
            beam.kiss(cfg.buds[i]);
        }

        // --- Configure the mom ---

        // Let the chief's hat call stop() without delay
        mom.setAuthority(chainlog.getAddress("MCD_ADM"));

        // --- Chainlog ---

        chainlog.setAddress(cfg.beamKey, address(beam));
        chainlog.setAddress(cfg.momKey,  address(mom));
    }
}
