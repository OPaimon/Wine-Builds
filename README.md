# Spritz-Wine-TkG

`Spritz-Wine-TkG` is a custom Wine build aimed at making playing certain
anime games easier, without missing any of Wine's latest additions.

## Download

Spritz-Wine builds are available in all [an-anime-team](https://github.com/an-anime-team)'s launchers, but you can also download the latest version from the repository's [releases](https://github.com/NelloKudo/Wine-Builds/releases).

## Features:

- Fixes various issues with **certain anime games**, from launch issues to hanging on exit
- Rebased to **latest wine-staging**
- Bundles all **esync/fsync/ntsync** in the same build, with latter used by default if possible
- Includes many of Wine-TkG's fixes
- Backported and reworked many patches from Proton, mostly aiming controllers
- Includes some QoL fixes for dropping inputs, random crashes and alt-tabbing.

TO-DO: add env. vars to README

## Builds description

Spritz builds are built in a Docker container based on Proton's SDK, with a few changes you can see in the Dockerfile. The `wine-builder` container is hosted [here](https://hub.docker.com/r/nellokudo/wine-builder), built from its apposite [GitHub CI](https://github.com/NelloKudo/WineBuilder/actions/workflows/dockerhub.yml) from my main repository of [WineBuilder](https://github.com/NelloKudo/WineBuilder).

Many thanks to spectator's work in the main repository for the polished building process.