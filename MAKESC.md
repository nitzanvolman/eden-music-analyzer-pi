# Building SuperCollider 3.14.1 + sc3-plugins on macOS

Build SuperCollider and sc3-plugins from source on macOS, pinned to version 3.14.1.

## Prerequisites

```bash
brew install cmake qt@5 libsndfile fftw
```

## Build directory

```bash
export SC_BUILD_DIR=~/sc-build
mkdir -p "$SC_BUILD_DIR"
```

## Step 1: Build SuperCollider

```bash
cd "$SC_BUILD_DIR"
git clone --recurse-submodules --branch Version-3.14.1 \
  https://github.com/supercollider/supercollider.git sc-source

cd sc-source
mkdir build && cd build

cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$(brew --prefix qt@5)" \
  -DSUPERNOVA=OFF \
  -DSC_EL=OFF \
  -DSC_VIM=OFF

make -j$(sysctl -n hw.ncpu)
```

This produces `SuperCollider.app` in the build directory. Build takes 10–20 minutes.

### Install

```bash
# Remove old Homebrew version if present
brew uninstall --cask supercollider 2>/dev/null || true

# Copy to Applications
cp -R "SuperCollider.app" /Applications/
```

## Step 2: Build sc3-plugins

sc3-plugins provides the UGens this project needs beyond SC core: Loudness, Onsets, MFCC, SpecCentroid, SpecFlatness, KeyTrack, BeatTrack2, and Chromagram (via bundled SCMIRUGens).

```bash
cd "$SC_BUILD_DIR"
git clone --recurse-submodules \
  https://github.com/supercollider/sc3-plugins.git

cd sc3-plugins
mkdir build && cd build

cmake .. \
  -DSC_PATH="$SC_BUILD_DIR/sc-source" \
  -DCMAKE_BUILD_TYPE=Release \
  -DSUPERNOVA=OFF

make -j$(sysctl -n hw.ncpu)
```

Build takes 2–5 minutes.

### Install plugins

```bash
SC_EXT="$HOME/Library/Application Support/SuperCollider/Extensions/SC3plugins"
mkdir -p "$SC_EXT"

# Compiled UGen binaries
find . -name "*.scx" -exec cp {} "$SC_EXT/" \;

# SC class files (sclang needs these to know about the UGens)
find .. -name "*.sc" -not -path "*/build/*" -not -path "*/.git/*" -exec cp {} "$SC_EXT/" \;
```

## Step 3: Verify

Launch SuperCollider from `/Applications/SuperCollider.app`, then evaluate:

```supercollider
// Should all print: true
'Chromagram'.asClass.notNil;
'Onsets'.asClass.notNil;
'MFCC'.asClass.notNil;
'KeyTrack'.asClass.notNil;
```

Check for API version mismatch errors in the post window on startup — there should be none since SC and plugins were built from the same source.

## Cleanup (optional)

```bash
rm -rf "$SC_BUILD_DIR"
```

## Troubleshooting

**Qt not found during cmake**
Make sure Qt 5 is installed and the cmake prefix path is correct:
```bash
brew install qt@5
echo $(brew --prefix qt@5)  # should print something like /opt/homebrew/opt/qt@5
```

**API version mismatch after upgrade**
If you later upgrade SuperCollider.app (e.g., via Homebrew), you must rebuild sc3-plugins against the new version. The SC source tag must match the app version.

**Chromagram class not found**
The `.sc` class files weren't copied to the Extensions directory. Re-run the plugin install step and restart SuperCollider.
