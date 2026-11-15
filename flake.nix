{
  description = "kata";

  nixConfig = {
    extra-substituters = [ "https://kata.cachix.org" ];
    extra-trusted-public-keys = [ "kata.cachix.org-1:l3Qa7glGu6EVSEYAoH7tqWXacHx7ghhYUbBGPucxmm8=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    shq.url = "github:aca/shq";
    qwer.url = "github:aca/qwer";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;
      tools = [
        "shq"
        "qwer"
      ];
      allSystems = [
        "x86_64-linux" # 64-bit Intel/AMD Linux
        "aarch64-linux" # 64-bit ARM Linux
        "aarch64-darwin" # 64-bit ARM macOS
      ];
      forAllSystems =
        f:
        lib.genAttrs allSystems (
          system:
          f {
            inherit system;
            pkgs = nixpkgs.legacyPackages.${system};
          }
        );

      # nixConfig only applies when the kata flake is used directly; consumers
      # importing kata as an input get the cache through this module.
      module =
        { pkgs, ... }:
        {
          nix.settings = {
            substituters = [ "https://kata.cachix.org" ];
            trusted-public-keys = [ "kata.cachix.org-1:l3Qa7glGu6EVSEYAoH7tqWXacHx7ghhYUbBGPucxmm8=" ];
          };
          environment.systemPackages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.default ];
        };
    in
    {
      packages = forAllSystems (
        {
          system,
          pkgs,
        }:
        let
          # Only the tools that support this system.
          bins =
            lib.filterAttrs (_: v: v != null) (
              lib.genAttrs tools (n: inputs.${n}.packages.${system}.default or null)
            )
            // local;

          # Go apps in this repo, one per cmd/<name>.
          local = lib.genAttrs (lib.attrNames (builtins.readDir ./cmd)) (
            name:
            pkgs.buildGoModule {
              pname = name;
              version = "0.0.0";
              src = lib.fileset.toSource {
                root = ./.;
                fileset = lib.fileset.unions [
                  ./go.mod
                  ./cmd/${name}
                ];
              };
              subPackages = [ "cmd/${name}" ];
              vendorHash = null;
              meta.mainProgram = name;
            }
          );
        in
        bins
        // {
          default = pkgs.buildEnv {
            name = "kata";
            paths = lib.attrValues bins;
          };
        }
      );

      overlays.default = final: prev: {
        kata = self.packages.${final.stdenv.hostPlatform.system}.default;
      };

      nixosModules.default = module;
      darwinModules.default = module;

      # `nix develop` provides a shell containing development tools.
      devShell = forAllSystems (
        {
          system,
          pkgs,
        }:
        pkgs.mkShell {
          buildInputs = with pkgs; [
            go_1_27
          ];
        }
      );
    };
}
