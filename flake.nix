{
  description = "Brainfuck compiler written in Zig";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: 
  let 
    systems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    packages = forAllSystems (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        default = pkgs.stdenv.mkDerivation {
          pname = "BFCompiler";
          version = "0.0.0";

          src = ./.;

          nativeBuildInputs = [
            pkgs.zig_0_16
          ];

          zigBuildFlags = [
            "-Doptimize=ReleaseSafe"
          ];

          # for `zig build test`
          dontUseZigCheck = true;
        };
      });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.mkShell {
            packages = [
              pkgs.zig
              pkgs.zls
              pkgs.gdb
              pkgs.pkg-config
            ];

            shellHook = ''
              export ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-global-cache"
              export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache"
            '';
          };
        });
  };
}
