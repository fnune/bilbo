# Bilbo

My media server.

## Running in a VM

Warning: security measures are waived for the VM in order to facilitate testing.

```sh
# Build the VM:
nixos-rebuild build-vm --flake .#bilboVirtual

# Run the VM:
./result/bin/run-bilbo-vm
```

After having changed `configuration.nix` or any of its dependencies:

```sh
# Remove the VM's state:
rm ./bilbo.qcow2
```
