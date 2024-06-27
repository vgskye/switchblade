{
  inputs.nixpkgs.url = "nixpkgs";

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    version = builtins.substring 0 7 self.lastModifiedDate;

    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];

    forAllSystems = nixpkgs.lib.genAttrs systems;
    nixpkgsFor = forAllSystems (system: import nixpkgs {inherit system;});

    packageFn = pkgs:
      pkgs.rustPlatform.buildRustPackage {
        pname = "switchblade";
        inherit version;

        nativeBuildInputs = [
          pkgs.pkg-config
        ];

        buildInputs = [
          pkgs.libinput
        ];

        src = builtins.path {
          name = "source";
          path = ./.;
        };

        cargoLock = {
          lockFile = ./Cargo.lock;
        };

        separateDebugInfo = true;
      };
  in rec {
    packages = forAllSystems (s: let
      pkgs = nixpkgsFor.${s};
    in rec {
      switchblade = packageFn pkgs;
      default = switchblade;
    });

    devShells = forAllSystems (s: let
      pkgs = nixpkgsFor.${s};
      inherit (pkgs) mkShell;
    in {
      default = mkShell {
        packages = with pkgs; [pkg-config libinput];
      };
    });

    homeManagerModules = rec {
      switchblade = { config, lib, pkgs, ... }:
      with lib;
      let
        cfg = config.services.switchblade;
        toml = pkgs.formats.toml { };
      in {
        options = {
          services.switchblade = {
            enable =
              mkEnableOption "Enable Switchblade daemon";

            package = mkOption {
              default = packages.${pkgs.system}.switchblade;
              type = types.package;
              defaultText = literalExpression "packages.${pkgs.system}.switchblade";
              description = lib.mdDoc "Switchblade derivation to use";
            };

            config = mkOption {
              type = toml.type;
              example = literalExpression ''
                {
                  lid = {
                    on = "systemctl suspend";
                  };
                  tablet_mode = {
                    on = "gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true";
                    off = "gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled false";
                  };
                }
              '';
              description = lib.mdDoc "Switchblade configuration";
            };
          };
        };

        config = mkIf cfg.enable {
          xdg.configFile."switchblade.toml".source = toml.generate "switchblade.toml" cfg.config;

          systemd.user.services.switchblade = {
            Unit = {
              After = "graphical-session-pre.service";
              Description = "Switchblade daemon";
              PartOf = "graphical-session.target";
            };

            Install = {
              WantedBy = 
              ["graphical-session.target"];
            };

            Service = {
              Type = "simple";
              ExecStart = "${cfg.package}/bin/switchblade";
              Restart = "on-failure";
            };
          };
        };
      };
      default = switchblade;
    };
  };
}