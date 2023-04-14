{ lib
, stdenv
, fetchFromGitHub
, fetchurl
, substituteAll
, coreutils
, curl
, glxinfo
, gnugrep
, gnused
, xdg-utils
, dbus
, hwdata
, mangohud32
, addOpenGLRunpath
, appstream
, glslang
, makeWrapper
, mako
, meson
, ninja
, pkg-config
, unzip
, libXNVCtrl
, wayland
, libX11
, spdlog
, glew
, glfw
, nlohmann_json
, xorg
, gamescopeSupport ? true # build mangoapp and mangohudctl
}:

let
  # Derived from subprojects/imgui.wrap
  imgui = rec {
    version = "1.81";
    src = fetchFromGitHub {
      owner = "ocornut";
      repo = "imgui";
      rev = "refs/tags/v${version}";
      sha256 = "sha256-rRkayXk3xz758v6vlMSaUu5fui6NR8Md3njhDB0gJ18=";
    };
    patch = fetchurl {
      url = "https://wrapdb.mesonbuild.com/v2/imgui_${version}-1/get_patch";
      sha256 = "sha256-bQC0QmkLalxdj4mDEdqvvOFtNwz2T1MpTDuMXGYeQ18=";
    };
  };

  # Derived from subprojects/vulkan-headers.wrap
  vulkan-headers = rec {
    version = "1.2.158";
    src = fetchFromGitHub {
      owner = "KhronosGroup";
      repo = "Vulkan-Headers";
      rev = "v${version}";
      hash = "sha256-5uyk2nMwV1MjXoa3hK/WUeGLwpINJJEvY16kc5DEaks=";
    };
    patch = fetchurl {
      url = "https://wrapdb.mesonbuild.com/v2/vulkan-headers_${version}-2/get_patch";
      hash = "sha256-hgNYz15z9FjNHoj4w4EW0SOrQh1c4uQSnsOOrt2CDhc=";
    };
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "mangohud";
  version = "0.6.8";

  src = fetchFromGitHub {
    owner = "flightlessmango";
    repo = "MangoHud";
    rev = "refs/tags/v${finalAttrs.version}";
    fetchSubmodules = true;
    sha256 = "sha256-jfmgN90kViHa7vMOjo2x4bNY2QbLk93uYEvaA4DxYvg=";
  };

  outputs = [ "out" "doc" "man" ];

  # Unpack subproject sources
  postUnpack = ''(
    cd "$sourceRoot/subprojects"
    cp -R --no-preserve=mode,ownership ${imgui.src} imgui-${imgui.version}
    cp -R --no-preserve=mode,ownership ${vulkan-headers.src} Vulkan-Headers-${vulkan-headers.version}
  )'';

  env.NIX_CFLAGS_COMPILE = "-I${vulkan-headers.src}/include";

  patches = [
    # Hard code dependencies. Can't use makeWrapper since the Vulkan
    # layer can be used without the mangohud executable by setting MANGOHUD=1.
    (substituteAll {
      src = ./hardcode-dependencies.patch;

      path = lib.makeBinPath [
        coreutils
        curl
        glxinfo
        gnugrep
        gnused
        xdg-utils
      ];

      libdbus = dbus.lib;
      inherit hwdata;
    })
  ] ++ lib.optionals (stdenv.hostPlatform.system == "x86_64-linux") [
    # Support 32bit OpenGL applications by appending the mangohud32
    # lib path to LD_LIBRARY_PATH.
    #
    # This workaround is necessary since on Nix's build of ld.so, $LIB
    # always expands to lib even when running an 32bit application.
    #
    # See https://github.com/NixOS/nixpkgs/issues/101597.
    (substituteAll {
      src = ./opengl32-nix-workaround.patch;
      inherit mangohud32;
    })
  ];

  postPatch = ''(
    cd subprojects
    unzip ${imgui.patch}
    unzip ${vulkan-headers.patch}
  )'';

  mesonFlags = [
    "-Dwith_wayland=enabled"
    "-Duse_system_spdlog=enabled"
  ] ++ lib.optionals gamescopeSupport [
    "-Dmangoapp_layer=true"
    "-Dmangoapp=true"
    "-Dmangohudctl=true"
  ];

  nativeBuildInputs = [
    addOpenGLRunpath
    appstream
    glslang
    makeWrapper
    mako
    meson
    ninja
    pkg-config
    unzip

    # Only the headers are used from these packages
    # The corresponding libraries are loaded at runtime from the app's runpath
    libXNVCtrl
    wayland
    libX11
  ];

  buildInputs = [
    dbus
    spdlog
  ] ++ lib.optionals gamescopeSupport [
    glew
    glfw
    nlohmann_json
    xorg.libXrandr
  ];

  # Support 32bit Vulkan applications by linking in 32bit Vulkan layers
  # This is needed for the same reason the 32bit OpenGL workaround is needed.
  postInstall = lib.optionalString (stdenv.hostPlatform.system == "x86_64-linux") ''
    ln -s ${mangohud32}/share/vulkan/implicit_layer.d/MangoHud.json \
      "$out/share/vulkan/implicit_layer.d/MangoHud.x86.json"

    ${lib.optionalString gamescopeSupport ''
      ln -s ${mangohud32}/share/vulkan/implicit_layer.d/libMangoApp.json \
        "$out/share/vulkan/implicit_layer.d/libMangoApp.x86.json"
    ''}
  '';

  postFixup = ''
    # Add OpenGL driver path to RUNPATH to support NVIDIA cards
    addOpenGLRunpath "$out/lib/mangohud/libMangoHud.so"
    ${lib.optionalString gamescopeSupport ''
      addOpenGLRunpath "$out/bin/mangoapp"
    ''}

    # Prefix XDG_DATA_DIRS to support overlaying Vulkan apps without
    # requiring MangoHud to be installed
    wrapProgram "$out/bin/mangohud" \
      --prefix XDG_DATA_DIRS : "$out/share"
  '';

  meta = with lib; {
    description = "A Vulkan and OpenGL overlay for monitoring FPS, temperatures, CPU/GPU load and more";
    homepage = "https://github.com/flightlessmango/MangoHud";
    platforms = platforms.linux;
    license = licenses.mit;
    maintainers = with maintainers; [ kira-bruneau zeratax ];
  };
})
