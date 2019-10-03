# Label Sync

This makes use of kubernetes test-infra to setup the labels on our
repos.  Copy config_example.sh and edit the values with the
configuration you desire, and then run `make` to see a *dry run* of what
it would do.

To apply the changes, run `make confirm`
