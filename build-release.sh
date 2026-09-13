#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
codesign_identity="macarchy-codesign-certificate"
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

#############
### BUILD ###
#############

./build-docs.sh --release
./build-shell-completion.sh

./generate.sh
./script/check-uncommitted-files.sh
./generate.sh --build-version "$build_version" --codesign-identity "$codesign_identity" --generate-git-hash

swift build -c release --arch arm64 --arch x86_64 --product macarchy -Xswiftc -warnings-as-errors # CLI

# todo: make xcodebuild use the same toolchain as swift
# toolchain="$(plutil -extract CFBundleIdentifier raw ~/Library/Developer/Toolchains/swift-6.1-RELEASE.xctoolchain/Info.plist)"
# xcodebuild -toolchain "$toolchain" \
# Unfortunately, Xcode 16 fails with:
#     2025-05-05 15:51:15.618 xcodebuild[4633:13690815] Writing error result bundle to /var/folders/s1/17k6s3xd7nb5mv42nx0sd0800000gn/T/ResultBundle_2025-05-05_15-51-0015.xcresult
#     xcodebuild: error: Could not resolve package dependencies:
#       <unknown>:0: warning: legacy driver is now deprecated; consider avoiding specifying '-disallow-use-new-driver'
#     <unknown>:0: error: unable to execute command: <unknown>

rm -rf .release && mkdir .release

cd ./xcode
    xcode_configuration="Release"
    xcodebuild -version
    xcodebuild-pretty ../.release/xcodebuild.log clean build \
        -scheme Macarchy \
        -destination "generic/platform=macOS" \
        -configuration "$xcode_configuration" \
        -derivedDataPath .xcode-build
cd -

git checkout .

cp -r "xcode/.xcode-build/Build/Products/$xcode_configuration/macarchy.app" .release
cp -r .build/apple/Products/Release/macarchy .release

################
### SIGN CLI ###
################

codesign -s "$codesign_identity" .release/macarchy

################
### VALIDATE ###
################

expected_layout=$(cat <<EOF
.release/macarchy.app
.release/macarchy.app/Contents
.release/macarchy.app/Contents/_CodeSignature
.release/macarchy.app/Contents/_CodeSignature/CodeResources
.release/macarchy.app/Contents/MacOS
.release/macarchy.app/Contents/MacOS/macarchy
.release/macarchy.app/Contents/Resources
.release/macarchy.app/Contents/Resources/default-config.toml
.release/macarchy.app/Contents/Resources/AppIcon.icns
.release/macarchy.app/Contents/Resources/Assets.car
.release/macarchy.app/Contents/Info.plist
.release/macarchy.app/Contents/PkgInfo
EOF
)

if test "$expected_layout" != "$(find .release/macarchy.app)"; then
    echo "!!! Expect/Actual layout don't match !!!"
    find .release/macarchy.app
    exit 1
fi

check-universal-binary() {
    if ! file "$1" | grep --fixed-string -q "Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64"; then
        echo "$1 is not a universal binary"
        exit 1
    fi
}

check-contains-hash() {
    hash=$(git rev-parse HEAD)
    if ! strings "$1" | grep --fixed-string "$hash" > /dev/null; then
        echo "$1 doesn't contain $hash"
        exit 1
    fi
}

check-universal-binary .release/macarchy.app/Contents/MacOS/macarchy
check-universal-binary .release/macarchy

check-contains-hash .release/macarchy.app/Contents/MacOS/macarchy
check-contains-hash .release/macarchy

codesign -v .release/macarchy.app
codesign -v .release/macarchy

############
### PACK ###
############

mkdir -p ".release/macarchy-v$build_version/manpage" && cp .man/*.1 ".release/macarchy-v$build_version/manpage"
cp -r ./legal ".release/macarchy-v$build_version/legal"
cp -r .shell-completion ".release/macarchy-v$build_version/shell-completion"
cd .release
    mkdir -p "macarchy-v$build_version/bin" && cp -r macarchy "macarchy-v$build_version/bin"
    cp -r macarchy.app "macarchy-v$build_version"
    zip -r "macarchy-v$build_version.zip" "macarchy-v$build_version"
cd -

#################
### Brew Cask ###
#################
for cask_name in macarchy macarchy-dev; do
    ./script/build-brew-cask.sh \
        --cask-name "$cask_name" \
        --zip-uri ".release/macarchy-v$build_version.zip" \
        --build-version "$build_version"
done
