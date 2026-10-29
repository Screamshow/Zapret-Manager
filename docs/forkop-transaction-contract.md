# Forkop installation contract

Prepared on dev for the Forkop X 2.6.0 migration. Publication and final manager
release description/version still require discussion with the operator.

The installer advertises `# Forkop-Manager-Contract: five-section-v1`; the
installed backend contains `ZM_FLAVOR="forkop-five-section-v1"`. Forkop checks
these markers together with the Screamshow update source, actual files, five
routes and RPC health. A version comparison alone cannot identify this fork.

`ZM_FORKOP_TRANSACTION=1 sh ZapretManager_LuCI.sh` retains the regular payload
installation and RPC registration, but skips package installs, changing the
cron enabled state/log level, restoring a stale resolver backup and launching
the delayed watchdog. Forkop stages/restores files around this operation and
restarts cron only when it was already running. Existing standalone installer
behaviour is preserved when the variable is unset.

Required dependencies must be available before the transaction. In particular,
Forkop refuses to change the panel when uhttpd-mod-ubus is missing, and reports
that it must come from the firmware's native feeds. Optional unzip is not
silently installed inside a file rollback transaction.

The marker does not enable automatic panel updates. Existing panel state,
including the user's update/watch choices, is retained. Console launchers are
replaced only after the shared backend passes verification.

Checked with panel-contract, backend-behavior and ui-render. The Forkop X
repository records sandbox, package-upgrade, live RPC and recovery evidence
in `docs/dev-260-preparation-2026-10-29.md`. Test delivery used the dev candidate
only inside the existing VMware VM; production main/mirror were unchanged.
