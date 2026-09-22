# chore(cheval,flatline,status): shorten the headless env scrub, temp-file handling and flag parsing

Reduces the headless subprocess env scrub to credential variables only, drops the mktemp guards in flatline-orchestrator.sh, and simplifies loa-status.sh argument handling and colour setup.
