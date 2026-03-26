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
      # Qt is provided by Binary Ninja's bundled qt/ directory, NOT Nix.
      # The bundled PySide6/shiboken6/binaryninjaui are compiled against
      # the bundled Qt and are ABI-incompatible with Nix's Qt
      # (Qt_6_PRIVATE_API symbol version mismatch).
      libxkbcommon
      dbus
      wayland
      libxml2.out
    ];
    pythonDeps = [python3.pkgs.pip] ++ extraPythonDeps;
    appendRunpaths = ["${lib.getLib python3}/lib"];

    # Wayland EGL integration lib may not be in the bundled Qt
    autoPatchelfIgnoreMissingDeps = ["libQt6WaylandEglClientHwIntegration.so.*"];

    forceWaylandArgs = lib.optionals forceWayland [
      "--run"
      ''export QT_QPA_PLATFORM=wayland''
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

      # Point autoPatchelf at the bundled Qt so it resolves Qt deps from
      # there instead of Nix's Qt (which we removed from buildInputs).
      addAutoPatchelfSearchPath "$out/opt/binaryninja/qt"

      find $out -xtype l -print -delete
      cp ${desktopIcon} $out/share/pixmaps/binaryninja.png
      chmod +x $out/opt/binaryninja/binaryninja
      buildPythonPath "$pythonDeps"
      makeWrapper $out/opt/binaryninja/binaryninja $out/bin/binaryninja \
        --prefix PYTHONPATH : "$program_PYTHONPATH" \
        "''${forceWaylandArgs[@]}"

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

    dontWrapQtApps = true;
    meta = {
      mainProgram = "binaryninja";
    };
  }
