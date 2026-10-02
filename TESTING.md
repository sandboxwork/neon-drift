# Crown Campaign validation

Godot 4.6.3, 2026-10-02. All save-writing suites run in disposable directories with NEON_DRIFT_TEST_SAVE=1.

## Automated verification
- Main legacy gameplay and new menu navigation: 270 checks, zero failures
- Fresh-process save reload: 24 checks, zero failures
- Original persistence: 102 checks, zero failures
- Campaign v1/v2 persistence and migration: 197 checks, zero failures
- Existing cosmetic/physics regression: 1,045 checks, zero failures
- Campaign content/recipe boundaries/copy isolation: 720 checks, zero failures
- Campaign UI contracts and font-measured text bounds: 1,534 checks, zero failures (1,296 text draws)
- Campaign behavior: 352 checks + 104 fresh-process checkpoint checks, zero failures

Total: 4,348 assertions passed across the suites.

Campaign behavior covers mission progress and boss gating in every sector, all ships and evolutions, warned hazards and dash protection, relic choices, sector rewards, duplicate prevention, achievements, full vs practice completion, save/continue including pending intermission, legacy run restoration, new-run confirmation and failure/retry safety.

## Real update-loop simulation
The full campaign test uses normal 0.05-second _tick updates, movement inputs, ordinary weapon damage, natural bosses, real mission progress and earned level upgrades. The pilot is invulnerable specifically to verify progression; it does not establish human difficulty/balance. Initial run completed all three sectors in 414.95 simulated seconds, with 670 kills, 25 upgrade choices and level 26. Peak enemy count was 7 for this strong automated build. It does not artificially set sector times, objective counts, boss health, player build or damage in the full-run fixture. Targeted unit fixtures do set state deliberately. A separate normal-damage smoke uses regular movement/spawns/fire and no forced protection: 37.40 simulated seconds, 35 kills, five hull-damage events, coherent defeat at 0/5 hull and suspended run cleared.

Legacy ten-minute survival simulation also completed with actual Warden defeat, 36,001 frames / 600.02 simulated seconds, 1,155 kills and level 35; that pilot is also invulnerable. Cosmetic tests preserve gameplay determinism with FX/calm modes.

## Build
- Updated project loads headlessly without script errors
- Fresh Godot 4.6.3 Web resource pack export completed
- Pack loads and runs headlessly as a standalone main pack
- Existing matching official Godot 4.6.3 single-thread Web engine JS/WASM/worklets retained unchanged from the previously verified Radiant Expedition Web export
- HTML pack byte count updated to the new pack size
- This bundle validation itself performed no Git push or public deployment; see Deployment

## Deployment
GitHub Actions (`.github/workflows/deploy-pages.yml`) installs the official Godot 4.6.3 editor and Web export templates (SHA-256 pinned), runs all seven suites with NEON_DRIFT_TEST_SAVE=1 and a separate disposable XDG_DATA_HOME each, exports the Web build fresh from source and deploys it to https://sandboxwork.github.io/neon-drift/. The deployed `deploy-commit.txt` records the source commit.

## Graphics and browser limits
The active command workspace has no usable native display; an isolated local-only Xorg attempt could not establish local sockets. Font-based layout contracts pass, but this is not screenshot/pixel verification. Prior-version native captures are not evidence for the new campaign screens. The separate cloud desktop browser is logged out of ChatGPT, so the authenticated Library download route was unavailable. No new native screenshot was obtained; no prior capture is labeled as this release.

Browser WebGL2 playback, browser IndexedDB migration, audible sound and mobile/GPU performance have not been verified for this build. No full human campaign playthrough or balance tuning from human testing is claimed.

## Reproduce
Use a fresh disposable directory for each save-writing test:

    NEON_DRIFT_TEST_SAVE=1 XDG_DATA_HOME=$(mktemp -d) godot --headless --path . --script res://tests/test_campaign.gd

Other suites: test_game.gd, test_progression.gd, test_campaign_persistence.gd, test_visuals.gd, test_campaign_content.gd, test_campaign_ui.gd.
