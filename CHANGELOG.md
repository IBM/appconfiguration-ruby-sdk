## CHANGELOG

## [0.1.0-rc.1]

- Fix progressive rollout evaluation to append the rollout configuration `start_at`
  to the entity id when computing the normalized hash, matching the Go SDK.
- Add a shared `get_current_rollout_percentage` helper for progressive rollout lookups.
- Align `DEFAULT_USAGE_LIMIT` with the Go SDK (30) and use it as the metering
  split threshold.
- Fix the `INVALID_OPTIONS_PARAMETER` constant name used by `set_context` option
  validation.
- Remove stray debug `puts`/log output from the configuration extraction and load path.
- Add an RSpec test suite covering models, configuration utils, metering and
  feature/property evaluation (including progressive rollout).

## [0.1.0-rc.0] - 2026-06-16

- Initial release
