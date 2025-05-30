{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    nixpkgsFor = forAllSystems (system: import nixpkgs {inherit system;});
  in {
    packages = forAllSystems (
      system: let
        pkgs = nixpkgsFor.${system};
      in {
        default = pkgs.stdenv.mkDerivation {
          name = "zig-project";
          src = self;
          buildInputs = [pkgs.zig];
          buildPhase = ''
            export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
            zig build
          '';
          installPhase = ''
            mkdir -p $out/lib
            cp zig-out/lib/* $out/lib/
          '';
        };
      }
    );

    devShells = forAllSystems (
      system: let
        pkgs = nixpkgsFor.${system};
      in {
        default = pkgs.mkShell {
          buildInputs = [
            pkgs.zig
            pkgs.zls
          ];
        };
      }
    );
  };
}
