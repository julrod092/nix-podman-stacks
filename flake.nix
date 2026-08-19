{
  description = "Collection of opinionated rootless Podman stacks";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    search = {
      url = "github:NuschtOS/search";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    sops-nix,
    ...
  } @ inputs: let
    forAllSystems = nixpkgs.lib.genAttrs [
      "aarch64-linux"
      "i686-linux"
      "x86_64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    lib = nixpkgs.lib;
  in {
    homeModules = import ./modules/module_list.nix;
    templates.default = {
      description = "Nix Podman Stacks Starter";
      path = ./template;
    };
    homeConfigurations.ci = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages."x86_64-linux";
      modules = [
        sops-nix.homeManagerModules.sops
        self.homeModules.nps
        {
          home.stateVersion = "26.05";
          home.username = "ci";
          home.homeDirectory = "/home/ci";
        }
        ./ci_config.nix
      ];
    };
    homeConfigurations.monitoring-minimal = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages."x86_64-linux";
      modules = [
        self.homeModules.nps
        {
          home = {
            stateVersion = "26.05";
            username = "ci";
            homeDirectory = "/home/ci";
          };
          nps = {
            hostIP4Address = "192.0.2.1";
            hostUid = 1000;
            storageBaseDir = "/home/ci/stacks";
            externalStorageBaseDir = "/mnt/storage";
            stacks.monitoring = {
              enable = true;
              loki.enable = false;
              alloy.enable = false;
              podmanExporter.enable = false;
              alertmanager.enable = false;
            };
          };
        }
      ];
    };

    checks.x86_64-linux.monitoring-minimal = self.homeConfigurations.monitoring-minimal.activationPackage;

    packages = forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        docs = import ./docs/default.nix {
          inherit
            self
            pkgs
            inputs
            system
            lib
            ;
          inherit (self.packages.${system}) optionsJSON;
        };
      in
        docs
    );

    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
  };
}
