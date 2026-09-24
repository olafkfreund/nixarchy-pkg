{
  description = "nixarchy.pkg -- manage nixpkgs packages, services and NixOS options from the Omarchy shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAll (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in rec {
          default = nixarchy-pkg;

          # runCommand and a plain copy, deliberately: omarchy-plugin-validate
          # refuses ANY symlink inside a plugin folder, so symlinkJoin, a
          # wrapped binary or a linkFarm all fail validation at rebuild time.
          #
          # Only what the plugin is. The artifacts, the tests and the README
          # are for whoever reads the repository, not for the shell that
          # loads this.
          nixarchy-pkg = pkgs.runCommand "nixarchy-pkg"
            {
              meta = with pkgs.lib; {
                description = "Omarchy plugin for managing nixpkgs packages, services and NixOS options";
                homepage = "https://github.com/olafkfreund/nixarchy-pkg";
                license = licenses.mit;
                platforms = platforms.linux;
              };
            }
            ''
              mkdir -p "$out/bin"
              cp ${./manifest.json} "$out/manifest.json"
              for f in ${./Menu.qml} ${./Panel.qml} ${./Card.qml} \
                       ${./PkgModel.qml} ${./OptionForm.qml}; do
                cp "$f" "$out/$(basename "$f" | sed 's/^[a-z0-9]*-//')"
              done
              # The bar mark. Without it the widget draws nothing, and the
              # validator does not catch a missing asset -- only the manifest's
              # own entry points.
              mkdir -p "$out/assets"
              cp ${./assets/package.svg} "$out/assets/package.svg"
              cp ${./bin/nixarchy-pkg}      "$out/bin/nixarchy-pkg"
              cp ${./bin/nixarchy-pkg-keys} "$out/bin/nixarchy-pkg-keys"
              chmod +x "$out/bin/"*
            '';
        });

      checks = forAll (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          # The adapter is shellcheck-clean, and stays that way.
          shellcheck = pkgs.runCommand "nixarchy-pkg-shellcheck"
            { nativeBuildInputs = [ pkgs.shellcheck ]; }
            ''
              shellcheck ${./bin/nixarchy-pkg} ${./bin/nixarchy-pkg-keys} ${./tests/adapter.sh}
              touch "$out"
            '';

          # The manifest is what the shell validates at load, so a typo in it
          # is a plugin that silently never appears.
          manifest = pkgs.runCommand "nixarchy-pkg-manifest"
            { nativeBuildInputs = [ pkgs.jq ]; }
            ''
              jq -e '
                .schemaVersion == 1
                and (.id | startswith("omarchy.") | not)
                and (.kinds | index("menu"))
                and (.entryPoints.menu == "Menu.qml")
                and (.entryPoints.barWidget == "Panel.qml")
              ' ${./manifest.json} > /dev/null
              touch "$out"
            '';

          # The menu used to multiply every Style.font token by a flat 1.45.
          # Those tokens already follow `omarchy display text size`, so the
          # multiplier never made the menu scale-aware -- it just held the
          # menu 45% above the rest of the shell at every size, and reached
          # only the text this plugin draws, leaving the shell's own qs.Ui
          # widgets at 1x inside it (#38).
          no-text-multiplier = pkgs.runCommand "nixarchy-pkg-text-scale" { } ''
            # Every file: no second scale, under any name.
            for f in ${./Menu.qml} ${./Panel.qml} ${./Card.qml} \
                     ${./PkgModel.qml} ${./OptionForm.qml}; do
              if grep -nE 'textScale|uiScale|\bpx\(' "$f"; then
                echo "a text multiplier above; size from a Style.font.* token" >&2
                exit 1
              fi
            done
            # The three that carried it: every font size IS a token, so a
            # literal cannot creep back one line at a time. Panel.qml is
            # exempt from THIS rule only -- it sizes the badge's digits from
            # the badge's own height, a derived size with no multiplier in
            # it, and the loop above still covers it.
            for f in ${./Menu.qml} ${./Card.qml} ${./OptionForm.qml}; do
              if grep -nE 'font\.pixelSize:' "$f" |
                 grep -vE 'font\.pixelSize:[[:space:]]*Style\.font\.[a-zA-Z]+[[:space:]]*$'; then
                echo "font size above is not a bare Style.font.* token" >&2
                exit 1
              fi
            done
            touch "$out"
          '';

          # A literal colour survives a theme switch and looks wrong, and it
          # is the one visual bug a user cannot fix from their own config.
          no-hardcoded-colours = pkgs.runCommand "nixarchy-pkg-colours" { } ''
            for f in ${./Menu.qml} ${./Panel.qml} ${./Card.qml} \
                     ${./PkgModel.qml} ${./OptionForm.qml}; do
              if grep -nE '"#[0-9a-fA-F]{3,8}"' "$f"; then
                echo "hardcoded colour above; use a Color.* token" >&2
                exit 1
              fi
            done
            touch "$out"
          '';
        });

      devShells = forAll (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [ shellcheck jq qt6.qtdeclarative ];
          };
        });
    };
}
