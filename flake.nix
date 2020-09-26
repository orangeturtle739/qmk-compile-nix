{
  description = "Nix wrapper for the QMK";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-20.03";

  outputs = { self, nixpkgs }:
    let
      mkQmkCompile = qmk: system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          hjson = with pkgs.python3Packages;
            buildPythonPackage rec {
              pname = "hjson";
              version = "3.0.1";
              src = fetchPypi {
                inherit pname version;
                sha256 = "1yaimcgz8w0ps1wk28wk9g9zdidp79d14xqqj9rjkvxalvx2f5qx";
              };
              doCheck = false;
            };
          avrlibc = pkgs.pkgsCross.avr.libcCross;

          avr_incflags = pkgs.lib.concatStringsSep " " [
            "-isystem ${avrlibc}/avr/include"
            "-B${avrlibc}/avr/lib/avr5"
            "-L${avrlibc}/avr/lib/avr5"
            "-B${avrlibc}/avr/lib/avr35"
            "-L${avrlibc}/avr/lib/avr35"
            "-B${avrlibc}/avr/lib/avr51"
            "-L${avrlibc}/avr/lib/avr51"
          ];

          pythonEnv = pkgs.python3.withPackages (p:
            with p; [
              # requirements.txt
              appdirs
              argcomplete
              colorama
              hjson
              # requirements-dev.txt
              nose2
              flake8
              pep8-naming
              yapf
            ]);

          stuff = with pkgs; [
            coreutils
            dfu-programmer
            dfu-util
            diffutils
            git
            pkgsCross.avr.buildPackages.binutils-unwrapped
            pkgsCross.avr.buildPackages.gcc
            pkgsCross.arm-embedded.buildPackages.gcc
            avrlibc
            avrdude
            teensy-loader-cli
            gnumake
            gnugrep
            gnused
            gawk
            runtimeShellPackage
            findutils
          ];
        in pkgs.stdenv.mkDerivation {
          pname = "qmk-compile";
          version = "18";

          buildInputs = [ pkgs.makeWrapper ];

          phases = [ "buildPhase" ];
          buildPhase = ''
            mkdir -p $out/bin
            echo ${qmk}
            cat << EOF > $out/bin/qmk-compile
            #!${pkgs.runtimeShell}
            set -e
            START=\$(pwd)
            DIR=\$(mktemp -d)
            trap "{ rm -rf \$DIR; }" EXIT
            cp -a ${qmk} \$DIR/qmk
            DIR=\$DIR/qmk
            chmod -R +w \$DIR
            cp -a \$2 \$DIR/keyboards/\$1/keymaps/tocompile
            chmod -R +w \$DIR
            cd \$DIR
            make \$1:tocompile
            cp -a \$1_tocompile.hex \$START/out.hex
            EOF
            echo "no way"
            chmod +x $out/bin/qmk-compile
            wrapProgram $out/bin/qmk-compile --set PATH ${
              pkgs.lib.makeBinPath stuff
            } --set AVR_CFLAGS "${avr_incflags}" --set AVR_ASFLAGS "${avr_incflags}"
          '';
        };
      mkKeyboardFirmware = { name, keyboard, firmware, qmk, system }:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          tool = mkQmkCompile qmk system;
        in pkgs.stdenv.mkDerivation {
          name = "${name}.hex";

          phases = [ "buildPhase" ];
          buildPhase = ''
            ${tool}/bin/qmk-compile ${keyboard} ${firmware}
            mv out.hex $out
          '';
        };
    in { lib = { inherit mkQmkCompile mkKeyboardFirmware; }; };
}
