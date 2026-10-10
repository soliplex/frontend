#!/bin/bash
# Restructure a Flutter web build for cache busting.
#
# 'flutter build web' emits fixed asset names ('main.dart.js',
# 'flutter_bootstrap.js', 'canvaskit/', 'assets/'), so a browser holding
# cached copies keeps running an old client after an upgrade.  This script:
#
# 1. Moves every build artifact except 'index.html', 'manifest.json',
#    'favicon.png', and 'icons/' into a '<RELEASE_HASH>/' subdirectory.
# 2. Points the Flutter loader in 'flutter_bootstrap.js' at that directory.
# 3. Points 'index.html' at the moved 'flutter_bootstrap.js' and splash images.
#
# Each release then gets new asset URLs, and only the small 'index.html' has
# to be revalidated.
#
# The rewritten URLs are relative, so they resolve against the document's
# '<base href>': the build stays deployable under any path, by setting
# '--base-href' at build time or editing the '<base href>' in 'index.html'
# afterwards.
#
# Usage: RELEASE_HASH=<hash> ./scripts/post-build-cache-bust.sh [build_dir]
#   build_dir: Path to the Flutter 'build/web' directory
#              (default: /app/build/web)
#
# Environment:
#   RELEASE_HASH: Required.  A release tag or commit SHA naming the hashed
#                 directory; letters, digits, '.', '_', '+', and '-' only.

set -e

BUILD_DIR="${1:-/app/build/web}"

# Run sed with before/after verification, so a change in Flutter's output
# format fails the build rather than shipping a client that cannot load.
# Usage: verify_sed <file> <pattern> <replacement> <verify_after>
verify_sed() {
    local file="$1"
    local pattern="$2"
    local replacement="$3"
    local verify_after="$4"

    if ! grep -q "$pattern" "$file"; then
        echo "Error: Pattern '$pattern' not found in $file"
        echo "This may indicate Flutter's output format has changed."
        exit 1
    fi

    sed -i "s|$pattern|$replacement|g" "$file"

    if ! grep -q "$verify_after" "$file"; then
        echo "Error: Expected result '$verify_after' not found in $file after sed"
        echo "The sed replacement may have failed."
        exit 1
    fi

    echo "  Verified: $file"
}

if [ -z "$RELEASE_HASH" ]; then
    echo "Error: RELEASE_HASH environment variable is not set"
    exit 1
fi

# The hash becomes a directory name, a URL path segment, and part of a sed
# replacement, so restrict it to characters that are safe in all three.
if ! [[ "$RELEASE_HASH" =~ ^[A-Za-z0-9._+-]+$ ]]; then
    echo "Error: RELEASE_HASH '$RELEASE_HASH' contains characters other than"
    echo "letters, digits, '.', '_', '+', and '-'"
    exit 1
fi

echo "Using release hash: $RELEASE_HASH"
echo "Build directory: $BUILD_DIR"

if [ ! -d "$BUILD_DIR" ]; then
    echo "Error: Build directory does not exist: $BUILD_DIR"
    exit 1
fi

if [ ! -f "$BUILD_DIR/index.html" ]; then
    echo "Error: index.html not found in $BUILD_DIR"
    exit 1
fi

HASH_DIR="$BUILD_DIR/$RELEASE_HASH"
mkdir -p "$HASH_DIR"

echo "Moving assets to $HASH_DIR..."

# Keep the files browsers and PWA installs fetch by fixed name at the root.
for item in "$BUILD_DIR"/*; do
    basename=$(basename "$item")
    case "$basename" in
        index.html|manifest.json|favicon.png|icons|"$RELEASE_HASH")
            echo "  Keeping at root: $basename"
            ;;
        *)
            echo "  Moving to hash dir: $basename"
            mv "$item" "$HASH_DIR/"
            ;;
    esac
done

echo "Updating flutter_bootstrap.js..."

# Pass the loader a config naming where everything now lives:
# - entrypointBaseUrl: where to find 'main.dart.js'
# - assetBase: where to find runtime assets (fonts, images, JSON manifests).
#   Must be an absolute URL: package_info_plus calls 'Uri.origin' on it to
#   locate 'version.json', and 'Uri.origin' throws on a schemeless path, which
#   makes 'PackageInfo.fromPlatform()' fail on web.  Resolving it against
#   'document.baseURI' keeps it absolute while still following '<base href>'.
# - canvasKitBaseUrl: where to find CanvasKit, which 'entrypointBaseUrl' does
#   not cover when the build bundles it ('--no-web-resources-cdn')
verify_sed "$HASH_DIR/flutter_bootstrap.js" \
    "_flutter.loader.load()" \
    "_flutter.loader.load({config: {entrypointBaseUrl: \"$RELEASE_HASH/\", assetBase: new URL(\"$RELEASE_HASH/\", document.baseURI).href, canvasKitBaseUrl: \"$RELEASE_HASH/canvaskit/\"}})" \
    "entrypointBaseUrl"

echo "Updating index.html..."

verify_sed "$BUILD_DIR/index.html" \
    'src="flutter_bootstrap.js"' \
    "src=\"$RELEASE_HASH/flutter_bootstrap.js\"" \
    "$RELEASE_HASH/flutter_bootstrap.js"

# The splash images moved with the rest of the build.
if grep -q "splash/img/" "$BUILD_DIR/index.html"; then
    verify_sed "$BUILD_DIR/index.html" \
        "splash/img/" \
        "$RELEASE_HASH/splash/img/" \
        "$RELEASE_HASH/splash/img/"
else
    echo "  Skipped: No splash/img/ references found in index.html"
fi

# Record the hash for operators (e.g. 'curl <origin>/.release-hash').
echo "$RELEASE_HASH" > "$BUILD_DIR/.release-hash"

echo "Cache busting setup complete!"
echo "  - Release hash: $RELEASE_HASH"
echo "  - Assets moved to: $HASH_DIR"
echo "  - index.html updated to reference hashed assets"
