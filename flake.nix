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
              (python3.withPackages (ps: with ps; [
                python-lsp-server
              ]))
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              (python3.withPackages (ps: with ps; [
                websocket-client
              ]))
              chromium
              parallel
            ];

          shellHook = ''
            export VENV_DIR="$PWD/.venv"

            if [ ! -d "$VENV_DIR" ]; then
              python -m venv "$VENV_DIR"
            fi

            source "$VENV_DIR/bin/activate"

            if ! python -c "import resiliparse" >/dev/null 2>&1; then
              python -m pip install --upgrade pip wheel setuptools
              python -m pip install resiliparse fastwarc
            fi
          '';
        };
      }
    );
}
