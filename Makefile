PATH := ~/.solc-select/artifacts/solc-0.8.24:$(PATH)
certora-beam :; PATH=${PATH} certoraRun certora/RewardsBeam.conf$(if $(rule), --rule $(rule),)$(if $(results), --wait_for_results all,)
certora-mom  :; PATH=${PATH} certoraRun certora/RewardsBeamMom.conf$(if $(rule), --rule $(rule),)$(if $(results), --wait_for_results all,)
