# cycle-120 C-D7: this directory is a LIVE-FIRE TRIAL FIXTURE, not a repo test
# suite. Its test_*.py is copied to /tmp and run there by the trial runbook
# (grimoires/loa/runbooks/live-fire-weak-model-trial.md), never collected in
# the repo's own pytest run. Exclude the whole tree from in-repo discovery.
collect_ignore_glob = ["*"]
