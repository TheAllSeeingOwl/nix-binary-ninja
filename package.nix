{
  lib,
  stdenv,
  callPackage,
  fetchurl,
  auto-patchelf,
  autoPatchelfHook,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  unzip,
  libGL,
  glib,
  fontconfig,
  xorg,
  dbus,
  libxkbcommon,
  wayland,
  kdePackages,
  python3,
  libxml2,
  binaryNinjaEdition ? "personal",
  forceWayland ? false,
  overrideSource ? null,
  extraPythonDeps ? [],
}: let
  sources = callPackage ./sources.nix {};
  platformSources = sources.editions.${binaryNinjaEdition};
  source =
    if overrideSource != null
    then overrideSource
    else if builtins.hasAttr stdenv.hostPlatform.system platformSources
    then platformSources.${stdenv.hostPlatform.system}
    else throw "No source for system ${stdenv.hostPlatform.system}";
  desktopIcon = fetchurl {
    url = "https://docs.binary.ninja/img/logo.png";
    hash = "sha256-TzGAAefTknnOBj70IHe64D6VwRKqIDpL4+o9kTw0Mn4=";
  };
in
  stdenv.mkDerivation {
    pname = "binary-ninja";
    inherit (sources) version;
    src = source;
    nativeBuildInputs = [
      makeWrapper
      auto-patchelf
      autoPatchelfHook
      python3.pkgs.wrapPython
      kdePackages.wrapQtAppsHook
      copyDesktopItems
    ];
    buildInputs = [
      unzip
      libGL
      glib
      fontconfig
      xorg.libXi
      xorg.libXrender
      xorg.xcbutilimage
      xorg.xcbutilrenderutil
      kdePackages.qtbase
      kdePackages.qtdeclarative
      kdePackages.qtwayland
      libxkbcommon
      dbus
      wayland
      libxml2.out
    ];
    pythonDeps = [python3.pkgs.pip] ++ extraPythonDeps;
    appendRunpaths = ["${lib.getLib python3}/lib"];
    qtWrapperArgs = lib.optionals forceWayland [
      "--set"
      "QT_QPA_PLATFORM"
      "wayland"
    ];
    buildPhase = ":";

    desktopItems = [
      (makeDesktopItem {
        name = "Binary Ninja";
        exec = "binaryninja";
        icon = "binaryninja";
        desktopName = "Binary Ninja";
        comment = "Binary Ninja is an interactive decompiler, disassembler, debugger, and binary analysis platform built by reverse engineers, for reverse engineers";
        categories = ["Development"];
      })
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      mkdir -p $out/opt/binaryninja
      mkdir -p $out/share/pixmaps
      cp -r * $out/opt/binaryninja

      # Hide the entire Python tree from autoPatchelf. The bundled PySide6,
      # shiboken6, and binaryninjaui Python modules are all compiled against
      # Binary Ninja's bundled Qt. autoPatchelf would relink them against
      # Nix's Qt which has incompatible Qt_6_PRIVATE_API symbols.
      mv $out/opt/binaryninja/python3 $out/python3_bundled
      mv $out/opt/binaryninja/python $out/python_bundled

      rm -rf $out/opt/binaryninja/qt
      find $out/opt/binaryninja \
        \( -type f -o -type l \) \
        -name '*.so.*' \
        -not -name 'libbinaryninjacore.so.*' \
        -not -name 'libbinaryninjaui.so.*' \
        -not -name 'liblldb.so.*' \
        -delete
      find $out -xtype l -print -delete
      cp ${desktopIcon} $out/share/pixmaps/binaryninja.png
      chmod +x $out/opt/binaryninja/binaryninja
      buildPythonPath "$pythonDeps"
      makeWrapper $out/opt/binaryninja/binaryninja $out/bin/binaryninja \
        --prefix PYTHONPATH : "$program_PYTHONPATH" \
        "''${qtWrapperArgs[@]}"

      runHook postInstall
    '';

    # libxml2 soname changes now follow ABI breaks.
    # https://gitlab.gnome.org/GNOME/libxml2/-/issues/751
    # This is of course ultimately good, but we can't recompile binja
    # So let's just force it to use whatever NixOS has. It's Probably Fine™
    preFixup = ''
      patchelf $out/opt/binaryninja/plugins/lldb/lib/liblldb.so.* \
        --replace-needed libxml2.so.2 libxml2.so
    '';

    # Restore the Python trees after autoPatchelf so they keep their bundled
    # Qt/shiboken dependencies intact.
    postFixup = ''
      mv $out/python3_bundled $out/opt/binaryninja/python3
      mv $out/python_bundled $out/opt/binaryninja/python
    '';

    dontWrapQtApps = true;
    meta = {
      mainProgram = "binaryninja";
    };
  }
