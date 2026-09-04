{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default =
          let
            pythonEnv = pkgs.python3.withPackages (
              ps:
              with ps;
              [ python-lsp-server ]
              ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
                websocket-client
              ]
            );
          in
          pkgs.mkShell {
            packages =
              with pkgs;
              [
                zig
                zls
                git
                nixfmt
                pythonEnv
              ]
              ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
                chromium
                parallel
              ];
          };
      }
    );
}
