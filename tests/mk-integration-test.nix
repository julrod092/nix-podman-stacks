# Builds a NixOS VM integration test from a list of Home Manager modules.
#
# Exported as `nix-podman-stacks.lib.mkIntegrationTest` and used by this repository's
# own `integrationTests` output, so both share one code path. Docs: docs/book/testing.md
{
  self,
  home-manager,
}: {
  pkgs,
  name ? "nps-integration",
  modules ? [],
  # Extra `_module.args` for the Home Manager test user.
  extraSpecialArgs ? {},
  extraNixosModules ? [],
  # `null` derives the units from the podman containers, `[]` disables the unit check.
  expectedUnits ? null,
  extraExpectedUnits ? [],
  # Python appended to the driver, runs after the unit check passed.
  extraTestScript ? "",
  # Replaces the driver entirely, including the unit check.
  testScript ? null,
  # `null` defers to the npsTests.memorySize Home Manager option.
  memorySize ? null,
  diskSize ? 8192,
  # Shared budget for all units to reach `active (running)`, not per unit.
  waitTimeout ? 600,
  stabilityGrace ? 60,
  # Derived from the two timeouts above when null.
  globalTimeout ? null,
}: let
  lib = pkgs.lib;

  checkBudget = waitTimeout + stabilityGrace;

  defaultTestScript =
    ''
      # The check script runs inside the VM, where check.conf is out of reach, so
      # the budget is passed in here. Plus headroom to boot and collect results.
      CHECK_TIMEOUT = ${toString (checkBudget + 120)};
    ''
    + builtins.readFile ./driver.py
    + lib.optionalString (extraTestScript != "") ''

      print("=== extra test script ===")
      ${extraTestScript}
    '';

  # Options declared by an imported module only exist in the node module system, so
  # they must be set from a module too, not from the outer `nodes.machine` definition.
  testOptionsModule = {...}: {
    npsTest = {
      inherit
        diskSize
        expectedUnits
        extraExpectedUnits
        stabilityGrace
        waitTimeout
        ;
      # `null` is a valid value here, it defers to npsTests.memorySize
      memorySize = lib.mkDefault memorySize;
      homeManagerModules = modules;
    };

    home-manager.extraSpecialArgs = extraSpecialArgs;
  };
in
  if !pkgs.stdenv.hostPlatform.isLinux
  then throw "lib.mkIntegrationTest: only Linux is supported, got ${pkgs.stdenv.hostPlatform.system}"
  else
    pkgs.testers.runNixOSTest {
      inherit name;

      globalTimeout =
        if globalTimeout == null
        then lib.max 1800 (checkBudget + 600)
        else globalTimeout;

      nodes.machine = {...}: {
        imports =
          [
            (import ./base-config.nix {
              inherit
                home-manager
                self
                ;
            })
            testOptionsModule
          ]
          ++ extraNixosModules;
      };

      testScript =
        if testScript == null
        then defaultTestScript
        else testScript;
    }
