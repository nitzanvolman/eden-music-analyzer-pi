# Building SuperCollider 3.14.1 + sc3-plugins on macOS

This guide builds SuperCollider and sc3-plugins (including Chromagram) from source on macOS, pinned to version 3.14.1 to match the pre-built SuperCollider.app.

## Why build from source?

The Homebrew cask (`brew install --cask supercollider`) installs a pre-built SuperCollider.app, but its sc3-plugins may not include all UGens needed by this project (notably Chromagram from SCMIRUGens). Building sc3-plugins from source against the matching SC version ensures all required UGens are available.

## Prerequisites

```bash
brew install cmake
```

You also need SuperCollider.app installed (for the runtime):

```bash
brew install --cask supercollider
```

Check your installed version — this guide targets 3.14.1:

```bash
ls /Applications/SuperCollider.app/Contents/Info.plist
# Open SuperCollider IDE → Help → About to confirm version
```

## Build directory

All source clones go in a single directory. Adjust the path if you prefer somewhere else:

```bash
export SC_BUILD_DIR=~/sc-build
mkdir -p "$SC_BUILD_DIR"
```

## Step 1: Clone SuperCollider source (headers only)

We need the SC source headers to compile plugins against. Must match your installed version.

```bash
cd "$SC_BUILD_DIR"
git clone --depth 1 --recurse-submodules --branch Version-3.14.1 \
  https://github.com/supercollider/supercollider.git sc-source
```

## Step 2: Clone and build sc3-plugins

sc3-plugins includes all the UGens this project uses beyond SC core: Loudness, Onsets, MFCC, SpecCentroid, SpecFlatness, KeyTrack, BeatTrack2, and Chromagram (via the bundled SCMIRUGens).

```bash
cd "$SC_BUILD_DIR"
git clone --depth 1 --recurse-submodules \
  https://github.com/supercollider/sc3-plugins.git

cd sc3-plugins
mkdir build && cd build
cmake .. -DSC_PATH="$SC_BUILD_DIR/sc-source" -DCMAKE_BUILD_TYPE=Release
make -j$(sysctl -n hw.ncpu)
```

Build takes 2–5 minutes depending on your Mac.

### Verify Chromagram was built

```bash
ls ../SCMIRUGens/
# Should contain Chromagram.cpp and other source files

find . -name "*.scx" | head -5
# Should list compiled UGen binaries
```

## Step 3: Install plugins

Copy the compiled plugins and SC class files to your SuperCollider Extensions directory:

```bash
SC_EXT="$HOME/Library/Application Support/SuperCollider/Extensions/SC3plugins"
mkdir -p "$SC_EXT"

# Copy compiled UGen binaries
find . -name "*.scx" -exec cp {} "$SC_EXT/" \;

# Copy SC class files (needed for sclang to know about the UGens)
find .. -name "*.sc" -not -path "*/build/*" -not -path "*/.git/*" -exec cp {} "$SC_EXT/" \;
```

## Step 4: Verify

Restart SuperCollider (quit and relaunch), then evaluate in the IDE or sclang:

```supercollider
// Should all print: true
'Chromagram'.asClass.notNil;
'Onsets'.asClass.notNil;
'MFCC'.asClass.notNil;
'KeyTrack'.asClass.notNil;
```

If you see `API version mismatch` errors on startup, you built against the wrong SC source version. Re-clone with the correct `--branch Version-X.Y.Z` tag matching your SuperCollider.app.

## Cleanup (optional)

The source directories are only needed for building. You can remove them after install:

```bash
rm -rf "$SC_BUILD_DIR"
```

## Troubleshooting

**API version mismatch**
The sc3-plugins were built against a different SC version than your installed SuperCollider.app. Check your app version and re-clone the SC source with the matching tag:
```bash
# List available version tags
git ls-remote --tags https://github.com/supercollider/supercollider.git | grep 'Version-3'
```

**Chromagram class not found**
The `.sc` class files weren't copied to the Extensions directory. Re-run the class file copy step and restart SuperCollider.

**cmake can't find SC headers**
Make sure `-DSC_PATH` points to the directory containing `SCVersion.txt` (the root of the SC source clone, not a subdirectory).
