# This file was generated by pkgs.mastodon.updateScript.
{ fetchgit, applyPatches }: let
  src = fetchgit {
    url = "https://github.com/tootsuite/mastodon.git";
    rev = "v3.5.0";
    sha256 = "1181zqz7928b6mnp4p502gy2rrwxyv5ysgfydx0n04y8wiq00g48";
  };
in applyPatches {
  inherit src;
  patches = [];
}
