# Public helpers, exported as the `lib` flake output. Mainly `mkIntegrationTest`, which
# lets consumers run this repository's own kind of integration test against their own
# configuration. Docs: docs/book/testing.md
{
  self,
  home-manager,
  lib,
}: {
  # Activates Home Manager modules as the `ci` user in a VM and verifies that all
  # stack services reach a stable `active (running)` state.
  mkIntegrationTest = import ../tests/mk-integration-test.nix {
    inherit
      home-manager
      self
      ;
  };

  # Per-stack test modules of this repository, e.g. `stackTestModules.immich`.
  stackTestModules =
    lib.mapAttrs (
      name: _: ../modules/${name}/vm-test.nix
    ) (lib.filterAttrs (
      name: _: builtins.pathExists ../modules/${name}/vm-test.nix
    ) (import ../modules/module_list.nix));
}
