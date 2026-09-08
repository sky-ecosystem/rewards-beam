# rewards-beam

`RewardsBeam` lets a facilitator multisig re-rate the vesting stream that funds a treasury-funded
farm, within boundaries set by Sky governance. It is the on-chain equivalent of the
[`TreasuryFundedFarmingInit.updateFarmVest`](https://github.com/sky-ecosystem/endgame-toolkit/blob/db3cc6a4cc4852f3677055b7a37dbd0492ce2f9c/script/dependencies/treasury-funded-farms/TreasuryFundedFarmingInit.sol#L128)
routine that governance spells run today.

## `set(vestTot)`

One call performs the whole rollover atomically:

1. flush whatever the outgoing stream still owes the farm (`dist.distribute()`),
2. retire it (`vest.yank`),
3. create the replacement stream, beginning now, and restrict it (`vest.create` + `vest.restrict`),
4. point the distribution contract at it (`dist.file("vestId", …)`).

The new stream's `bgn` is hardcoded to `block.timestamp`, which is what every spell that ran this
routine used. That leaves a facilitator no way to shift emissions in time: a `bgn` in the past would
make part of the stream claimable on creation and drop it into the farm at once, and a `bgn` in the
future would stall emissions until it arrived. It also means nothing has accrued when the stream is
created, so no distribution follows — the distribution job picks it up from here.

## Boundaries

Governance `file`s each knob. A freshly deployed beam is **inert**: `maxVestTot` defaults to `0`, so
nothing can be executed until governance files it.

| Param        | Unit    | Bounds                                                     |
| ------------ | ------- | ---------------------------------------------------------- |
| `maxVestTot` | wad     | max total of a new stream                                   |
| `vestTau`    | s       | duration of a new stream; must be non-zero, defaults to `90 days` |
| `tau`        | s       | cooldown between `set()` calls                              |
| `toc`        | unix ts | last `set()` timestamp                                      |

The facilitator sets one number: how much to stream. `vestTau` is governance-only, so the rate a
facilitator can reach is bounded by `maxVestTot / vestTau`, both ends governance-owned. Lowering
`vestTot` is unbounded: at worst it starves the farm, which governance can revive, and the funds
simply stay in the treasury.

### Treasury funding is governance's job, not the beam's

The beam is not the treasury and cannot `approve` on its behalf, so — unlike the spell routine — it
does not adjust the treasury's gem allowance to `vest`. It does not check it either. A pre-flight
check would be worth little:

- The allowance is a bookkeeping figure the treasury balance does not necessarily back.
- `DssVest` draws `unpaid` progressively over `vestTau`, never `vestTot` at once, so requiring
  up-front coverage is stricter than the system needs.
- The token already caps cumulative transfers at the allowance, on every distribution, with or
  without the beam looking.

The funding check that matters comes for free: `set()` flushes the outgoing stream first, which moves
real tokens, so the call reverts if the treasury cannot cover what is currently due. Keeping the
stream payable from there on is governance's job, exactly as it is when the balance runs low. The
beam's own boundary is `maxVestTot`.

`vest.cap()` is a second, independent governance-owned rate ceiling that `vest.create` enforces
anyway; the beam checks it up front only so the failure mode is legible. The beam is deliberately not
a `cap` filer — raising `cap` would affect every stream of the vest, not just this farm's.

The farm's `rewardsDuration` is deliberately out of scope: re-rating the notification window is a structural decision for the full governance process.
