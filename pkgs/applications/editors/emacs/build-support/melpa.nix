# builder for Emacs packages built for packages.el
# using MELPA package-build.el

{ lib, stdenv, fetchFromGitHub, emacs, texinfo, writeText }:

let
  handledArgs = [ "meta" "preUnpack" "postUnpack" ];
  genericBuild = import ./generic.nix { inherit lib stdenv emacs texinfo writeText; };

  packageBuild = stdenv.mkDerivation {
    name = "package-build";
    src = fetchFromGitHub {
      owner = "melpa";
      repo = "package-build";
      rev = "c48aa078c01b4f07b804270c4583a0a58ffea1c0";
      sha256 = "sha256-MzPj375upIiYXdQR+wWXv3A1zMqbSrZlH0taLuxx/1M=";
    };

    patches = [ ./package-build-dont-use-mtime.patch ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = "
      mkdir -p $out
      cp -r * $out
    ";
  };

in

{ /*
    pname: Nix package name without special symbols and without version or
    "emacs-" prefix.
  */
  pname
  /*
    ename: Original Emacs package name, possibly containing special symbols.
    Default: pname
  */
, ename ? pname
  /*
    version: Either a stable version such as "1.2" or an unstable version.
    An unstable version can use either Nix format (preferred) such as
    "1.2-unstable-2024-06-01" or MELPA format such as "20240601.1230".
  */
, version
  /*
    commit: Optional package history commit.
    Default: src.rev or "unknown"
    This will be written into the generated package but it is not needed during
    the build process.
  */
, commit ? (args.src.rev or "unknown")
  /*
    files: Optional recipe property specifying the files used to build the package.
    If null, do not set it in recipe, keeping the default upstream behaviour.
    Default: null
  */
, files ? null
  /*
    recipe: Optional MELPA recipe.
    Default: a minimally functional recipe
  */
, recipe ? (writeText "${pname}-recipe" ''
    (${ename} :fetcher git :url ""
              ${lib.optionalString (files != null) ":files ${files}"})
  '')
, preUnpack ? ""
, postUnpack ? ""
, meta ? {}
, ...
}@args:

genericBuild ({

  elpa2nix = ./elpa2nix.el;
  melpa2nix = ./melpa2nix.el;

  inherit packageBuild commit ename recipe;

  melpaVersion =
    let
      parsed = lib.flip builtins.match version
        # match <version>-unstable-YYYY-MM-DD format
        "^.*-unstable-([[:digit:]]{4})-([[:digit:]]{2})-([[:digit:]]{2})$";
      unstableVersionInNixFormat = parsed != null; # heuristics
      date = builtins.concatStringsSep "" parsed;
      time = "0"; # unstable version in nix format lacks this info
    in
    if unstableVersionInNixFormat
    then date + "." + time
    else version;

  preUnpack = ''
    mkdir -p "$NIX_BUILD_TOP/recipes"
    if [ -n "$recipe" ]; then
      cp "$recipe" "$NIX_BUILD_TOP/recipes/$ename"
    fi

    ln -s "$packageBuild" "$NIX_BUILD_TOP/package-build"

    mkdir -p "$NIX_BUILD_TOP/packages"
  '' + preUnpack;

  postUnpack = ''
    mkdir -p "$NIX_BUILD_TOP/working"
    ln -s "$NIX_BUILD_TOP/$sourceRoot" "$NIX_BUILD_TOP/working/$ename"
  '' + postUnpack;

  buildPhase = ''
    runHook preBuild

    cd "$NIX_BUILD_TOP"

    emacs --batch -Q \
        -L "$NIX_BUILD_TOP/package-build" \
        -l "$melpa2nix" \
        -f melpa2nix-build-package \
        $ename $melpaVersion $commit

    runHook postBuild
    '';

  installPhase = ''
    runHook preInstall

    archive="$NIX_BUILD_TOP/packages/$ename-$melpaVersion.el"
    if [ ! -f "$archive" ]; then
        archive="$NIX_BUILD_TOP/packages/$ename-$melpaVersion.tar"
    fi

    emacs --batch -Q \
        -l "$elpa2nix" \
        -f elpa2nix-install-package \
        "$archive" "$out/share/emacs/site-lisp/elpa"

    runHook postInstall
  '';

  meta = {
    homepage = args.src.meta.homepage or "https://melpa.org/#/${pname}";
  } // meta;
}

// removeAttrs args handledArgs)
