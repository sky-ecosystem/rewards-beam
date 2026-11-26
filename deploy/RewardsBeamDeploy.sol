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

import { ScriptTools } from "dss-test/ScriptTools.sol";
import { RewardsBeamInstance } from "./RewardsBeamInstance.sol";
import { RewardsBeam } from "src/RewardsBeam.sol";
import { RewardsBeamMom } from "src/RewardsBeamMom.sol";

// Deploy a RewardsBeam instance
library RewardsBeamDeploy {

    function deploy(
        address deployer,
        address owner,
        address dist
    ) internal returns (RewardsBeamInstance memory instance) {
        instance.beam = address(new RewardsBeam(dist));
        instance.mom  = address(new RewardsBeamMom(instance.beam));

        ScriptTools.switchOwner(instance.beam, deployer, owner);
        RewardsBeamMom(instance.mom).setOwner(owner);
    }
}
