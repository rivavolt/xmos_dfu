{
  description = "xmosdfu — JDS Labs XMOS USB DAC firmware flasher, with the iFi XU216 PID added";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          xmos-dfu = pkgs.stdenv.mkDerivation {
            pname = "xmos-dfu";
            version = "unstable-2026-06-21";

            # Build this repo's own source — the iFi XU216 PID lives in xmosdfu.cpp
            # (vendor 0x20b1 is upstream), so no fetch/patch indirection is needed.
            src = self;
            sourceRoot = "source/xmos_dfu";

            nativeBuildInputs = [ pkgs.pkg-config ];
            buildInputs = [ pkgs.libusb1 ];

            buildPhase = ''
              runHook preBuild
              make -f Makefile linux
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              install -Dm755 xmosdfu $out/bin/xmosdfu
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "CLI DFU utility for XMOS-based JDS Labs USB devices, with the iFi XU216 PID added";
              homepage = "https://github.com/rivavolt/xmos_dfu";
              license = licenses.mit;
              mainProgram = "xmosdfu";
              platforms = systems;
            };
          };
        in
        {
          default = xmos-dfu;
          xmos-dfu = xmos-dfu;
        }
      );
    };
}
