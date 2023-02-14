#!/usr/bin/env arch -x86_64 bash

set -e

printtag() {
    # GitHub Actions tag format
    echo "::$1::${2-}"
}

begingroup() {
    printtag "group" "$1"
}

endgroup() {
    printtag "endgroup"
}

export GITHUB_WORKSPACE=$(pwd)

if [ -z "$CROSS_OVER_VERSION" ]; then
    export CROSS_OVER_VERSION=22.1.0
    echo "CROSS_OVER_VERSION not set building crossover-wine-${CROSS_OVER_VERSION}"
fi

export CX_MAJOR="${CROSS_OVER_VERSION:0:2}"

# crossover source code to be downloaded
export CROSS_OVER_SOURCE_URL=https://media.codeweavers.com/pub/crossover/source/crossover-sources-${CROSS_OVER_VERSION}.tar.gz
export CROSS_OVER_LOCAL_FILE=crossover-${CROSS_OVER_VERSION}

# directories / files inside the downloaded tar file directory structure
export WINE_CONFIGURE=$GITHUB_WORKSPACE/sources/wine/configure

# build directories
export BUILDROOT=$GITHUB_WORKSPACE/build

# target directory for installation
export INSTALLROOT=$GITHUB_WORKSPACE/install
export PACKAGE_UPLOAD=$GITHUB_WORKSPACE/upload

# artifact name
export WINE_INSTALLATION=wine-cx${CROSS_OVER_VERSION}

# Need to ensure Instel brew actually exists
if ! command -v "/usr/local/bin/brew" &> /dev/null
then
    echo "</usr/local/bin/brew> could not be found"
    echo "An Intel brew installation is required"
    exit
fi

# Manually configure $PATH
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Library/Apple/usr/bin"


begingroup "Installing Dependencies"
# build dependencies
brew install   bison                \
               gcenx/wine/cx-llvm   \
               mingw-w64

# runtime dependencies for crossover-wine
brew install   freetype             \
               gnutls               \
               molten-vk            \
               sdl2
endgroup


export BISON="$(brew --prefix bison)/bin/bison"
export CC="$(brew --prefix cx-llvm)/bin/clang"
export CXX="${CC}++"
export CFLAGS="-g -O2 -Wno-deprecated-declarations -Wno-format"
export LDFLAGS="-Wl,-headerpad_max_install_names"

# avoid weird linker errors with Xcode 10 and later
export MACOSX_DEPLOYMENT_TARGET=10.14

# see https://github.com/Gcenx/macOS_Wine_builds/issues/17#issuecomment-750346843
export CROSSCFLAGS="-g -O2"

export ac_cv_lib_soname_MoltenVK="libMoltenVK.dylib"
export ac_cv_lib_soname_vulkan=""


begingroup "Download & extracting source"
if [[ ! -f ${CROSS_OVER_LOCAL_FILE}.tar.gz ]]; then
    curl -o ${CROSS_OVER_LOCAL_FILE}.tar.gz ${CROSS_OVER_SOURCE_URL}
fi


if [[ -d "${GITHUB_WORKSPACE}/sources" ]]; then
    rm -rf ${GITHUB_WORKSPACE}/sources
fi
tar xf ${CROSS_OVER_LOCAL_FILE}.tar.gz
endgroup


begingroup "Patch Add missing distversion.h"
# Patch provided by Josh Dubois, CrossOver product manager, CodeWeavers.
pushd sources/wine
patch -p1 < ${GITHUB_WORKSPACE}/distversion.patch
popd
endgroup

begingroup "Configure wine64-${CROSS_OVER_VERSION}"
mkdir -p ${BUILDROOT}/wine64-${CROSS_OVER_VERSION}
pushd ${BUILDROOT}/wine64-${CROSS_OVER_VERSION}
${WINE_CONFIGURE} \
        --enable-win64 \
        --disable-winedbg \
        --disable-tests \
        --without-alsa \
        --without-capi \
        --with-cms \
        --without-dbus \
        --without-gstreamer \
        --without-gsm \
        --without-gphoto \
        --without-inotify \
        --without-krb5 \
        --with-mingw \
        --without-openal \
        --without-oss \
        --with-png \
        --without-pulse \
        --without-sane \
        --with-sdl \
        --without-udev \
        --without-v4l2 \
        --without-usb \
        --without-vkd3d \
        --with-vulkan \
        --without-x
popd
endgroup


begingroup "Build wine64-${CROSS_OVER_VERSION}"
pushd ${BUILDROOT}/wine64-${CROSS_OVER_VERSION}
make -j$(sysctl -n hw.ncpu 2>/dev/null)
popd
endgroup


begingroup "Configure wine32on64-${CROSS_OVER_VERSION}"
mkdir -p ${BUILDROOT}/wine32on64-${CROSS_OVER_VERSION}
pushd ${BUILDROOT}/wine32on64-${CROSS_OVER_VERSION}
${WINE_CONFIGURE} \
        --enable-win32on64 \
        --disable-winedbg \
        --with-wine64=${BUILDROOT}/wine64-${CROSS_OVER_VERSION} \
        --disable-tests \
        --without-alsa \
        --without-capi \
        --without-cms \
        --without-dbus \
        --without-gstreamer \
        --without-gsm \
        --without-gphoto \
        --without-inotify \
        --without-krb5 \
        --with-mingw \
        --without-openal \
        --without-oss \
        --with-png \
        --without-pulse \
        --without-sane \
        --with-sdl \
        --without-udev \
        --without-v4l2 \
        --without-usb \
        --without-vkd3d \
        --with-vulkan \
        --without-x \
        --disable-loader
popd
endgroup


begingroup "Build wine32on64-${CROSS_OVER_VERSION}"
pushd ${BUILDROOT}/wine32on64-${CROSS_OVER_VERSION}
make -k -j$(sysctl -n hw.activecpu 2>/dev/null)
popd
endgroup


begingroup "Install wine32on64-${CROSS_OVER_VERSION}"
pushd ${BUILDROOT}/wine32on64-${CROSS_OVER_VERSION}
make install-lib DESTDIR="${INSTALLROOT}/${WINE_INSTALLATION}"
popd
endgroup


begingroup "Install wine64-${CROSS_OVER_VERSION}"
pushd ${BUILDROOT}/wine64-${CROSS_OVER_VERSION}
make install-lib DESTDIR="${INSTALLROOT}/${WINE_INSTALLATION}"
popd
endgroup


begingroup "Tar Wine"
pushd ${INSTALLROOT}
tar -czvf ${WINE_INSTALLATION}.tar.gz ${WINE_INSTALLATION}
popd
endgroup


begingroup "Upload Wine"
mkdir -p ${PACKAGE_UPLOAD}
cp ${INSTALLROOT}/${WINE_INSTALLATION}.tar.gz ${PACKAGE_UPLOAD}/
endgroup
