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
        devShells.default = pkgs.mkShell {
          packages =
            with pkgs;
            [
              zig
              zls
              git
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              (python3.withPackages (ps: with ps; [
                websocket-client
                python-lsp-server
              ]))
              chromium
              parallel
            ];
        };
      }
    );
}
