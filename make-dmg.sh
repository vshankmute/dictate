#!/bin/bash
# Builds dist/Dictate-<version>-arm64.dmg: Dictate.app with a static whisper-cli inside, for Apple Silicon.
# Needs Command Line Tools, git and cmake (brew install cmake).
# The internet is used only here, to fetch the whisper.cpp source; the app itself has no network code.
set -euo pipefail
cd "$(dirname "$0")"
VERSION="$(tr -d '[:space:]' < VERSION)"
WHISPER_TAG="v1.9.5"   # pinned: the version whose source was reviewed
WORK=".build"

[ "$(uname -m)" = "arm64" ] || { echo "The DMG is built for Apple Silicon (arm64)." >&2; exit 1; }
command -v cmake >/dev/null || { echo "cmake is missing: brew install cmake" >&2; exit 1; }

# 1. whisper-cli: static, Metal shaders embedded, no network backends, runs on any Apple Silicon Mac
mkdir -p "$WORK"
if [ ! -d "$WORK/whisper.cpp" ]; then
    git clone --depth 1 --branch "$WHISPER_TAG" https://github.com/ggml-org/whisper.cpp "$WORK/whisper.cpp"
fi
cmake -S "$WORK/whisper.cpp" -B "$WORK/whisper-build" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DGGML_NATIVE=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_RPC=OFF \
    -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF -DWHISPER_SDL2=OFF -DWHISPER_CURL=OFF
cmake --build "$WORK/whisper-build" -j --target whisper-cli

# 2. Dictate.app with whisper-cli next to the main executable
bash build.sh
cp "$WORK/whisper-build/bin/whisper-cli" Dictate.app/Contents/MacOS/whisper-cli
# MIT requires shipping the license text with the binaries: Dictate's own and whisper.cpp/ggml's.
# (whisper-cli also contains miniaudio and stb_vorbis, which are used under their public-domain option.)
mkdir -p Dictate.app/Contents/Resources/Licenses
cp LICENSE Dictate.app/Contents/Resources/Licenses/Dictate-LICENSE.txt
cp "$WORK/whisper.cpp/LICENSE" Dictate.app/Contents/Resources/Licenses/whisper.cpp-LICENSE.txt

# 3. Promise check: neither binary may call the network
for binary in Dictate.app/Contents/MacOS/Dictate Dictate.app/Contents/MacOS/whisper-cli; do
    if nm -u "$binary" | grep -qE '^_(socket|connect|getaddrinfo|curl_easy_init)$'; then
        echo "Network symbols found in $binary — not packaging." >&2
        exit 1
    fi
done
echo "whisper-cli links only to:"
otool -L Dictate.app/Contents/MacOS/whisper-cli | tail -n +2

# 4. Ad-hoc signature (inner binary first), then the DMG with an Applications shortcut
codesign --force --sign - Dictate.app/Contents/MacOS/whisper-cli
codesign --force --sign - Dictate.app
stage="$WORK/dmg"
rm -rf "$stage"
mkdir -p "$stage" dist
cp -R Dictate.app "$stage/"
ln -s /Applications "$stage/Applications"
dmg="dist/Dictate-$VERSION-arm64.dmg"
hdiutil create -volname "Dictate" -srcfolder "$stage" -ov -format UDZO "$dmg"
echo
echo "Done: $dmg"
shasum -a 256 "$dmg"
