#!/usr/bin/env arch -x86_64 bash

set -ex

echo Wine-Crossover-MacOS

export GITHUB_WORKSPACE=$(pwd)

if [ -z "$CROSS_OVER_VERSION" ]; then
    export CROSS_OVER_VERSION=22.0.1
    echo "CROSS_OVER_VERSION not set building crossover-wine-${CROSS_OVER_VERSION}"
fi

# avoid weird linker errors with Xcode 10 and later
export MACOSX_DEPLOYMENT_TARGET=10.9

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

# artifact names
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

echo Installing Dependencies
# build dependencies
brew install   bison                \
               gcenx/wine/cx-llvm   \
               mingw-w64

# runtime dependencies for crossover-wine
brew install   freetype             \
               gnutls               \
               gst-plugins-base     \
               molten-vk            \
               sane-backends        \
               sdl2

echo "Add cx-llvm & bison to PATH"
export PATH="$(brew --prefix cx-llvm)/bin":"$(brew --prefix bison)/bin":${PATH}


############ Download and Prepare Source Code ##############

echo Get Source
if [[ ! -f ${CROSS_OVER_LOCAL_FILE}.tar.gz ]]; then
    curl -o ${CROSS_OVER_LOCAL_FILE}.tar.gz ${CROSS_OVER_SOURCE_URL}
fi

echo Extract Source
if [[ -d "${GITHUB_WORKSPACE}/sources" ]]; then
    rm -rf ${GITHUB_WORKSPACE}/sources
fi
tar xf ${CROSS_OVER_LOCAL_FILE}.tar.gz

echo "Patch Add missing distversion.h"
# Patch provided by Josh Dubois, CrossOver product manager, CodeWeavers.
pushd sources/wine
patch -p1 < ${GITHUB_WORKSPACE}/distversion.patch
popd


export CC=clang
export CXX=$CC++
export CROSSCFLAGS="-g -O2"
export CFLAGS="$CROSSCFLAGS -Wno-deprecated-declarations"
export LDFLAGS="-Wl,-headerpad_max_install_names"

export ac_cv_lib_soname_vulkan=""
export ac_cv_lib_soname_MoltenVK="$(brew --prefix molten-vk)/lib/libMoltenVK.dylib"


############ BuildTools 64bit ##############

echo "Configure winetools64-${CROSS_OVER_VERSION}"
mkdir -p ${BUILDROOT}/winetools64-${CROSS_OVER_VERSION}
pushd ${BUILDROOT}/winetools64-${CROSS_OVER_VERSION}
${WINE_CONFIGURE} \
        --disable-option-checking \
        --enable-win64 \
        --disable-tests \
        --without-alsa \
        --without-capi \
        --without-dbus \
        --without-gphoto \
        --without-inotify \
        --without-oss \
        --without-pulse \
        --without-udev \
        --without-usb \
        --without-v4l2 \
        --without-gsm \
        --with-mingw \
        --with-png \
        --with-sdl \
        --without-krb5 \
        --with-vulkan \
        --without-x
popd

echo "Build winetools64-${CROSS_OVER_VERSION}"
pushd ${BUILDROOT}/winetools64-${CROSS_OVER_VERSION}
make __tooldeps__ -j$(sysctl -n hw.ncpu 2>/dev/null)

# cross-compiling of wine is broken due to nls not building (wine-7.6)
# https://bugs.winehq.org/show_bug.cgi?id=52834
if [ -d "$(pwd)/nls" ]; then make -C nls; fi
popd


############ Build 64bit Version ##############

echo "Configure wine64-${CROSS_OVER_VERSION}"
mkdir -p ${BUILDROOT}/wine64-${CROSS_OVER_VERSION}
pushd ${BUILDROOT}/wine64-${CROSS_OVER_VERSION}
${WINE_CONFIGURE} \
        --disable-option-checking \
        --with-wine-tools=${BUILDROOT}/winetools64-${CROSS_OVER_VERSION} \
        --enable-win64 \
        --disable-tests \
        --without-alsa \
        --without-capi \
        --without-dbus \
        --without-gphoto \
        --without-inotify \
        --without-oss \
        --without-pulse \
        --without-udev \
        --without-usb \
        --without-v4l2 \
        --without-gsm \
        --with-mingw \
        --with-png \
        --with-sdl \
        --without-krb5 \
        --with-vulkan \
        --without-x
popd

echo "Build wine64-${CROSS_OVER_VERSION}"
pushd ${BUILDROOT}/wine64-${CROSS_OVER_VERSION}
make -j$(sysctl -n hw.ncpu 2>/dev/null)
popd


############ Build 32bit Version (WoW64) ##############

echo "Configure wine32on64-${CROSS_OVER_VERSION}"
mkdir -p ${BUILDROOT}/wine32on64-${CROSS_OVER_VERSION}
pushd ${BUILDROOT}/wine32on64-${CROSS_OVER_VERSION}
${WINE_CONFIGURE} \
        --disable-option-checking \
        --enable-win32on64 \
        --with-wine64=${BUILDROOT}/wine64-${CROSS_OVER_VERSION} \
        --with-wine-tools=${BUILDROOT}/winetools64-${CROSS_OVER_VERSION} \
        --disable-tests \
        --without-alsa \
        --without-capi \
        --without-dbus \
        --without-gphoto \
        --without-inotify \
        $([[ ${CROSS_OVER_VERSION} ge 22.0.0 ]] && echo "--without-openal" || echo "--with-openal") \
        --without-oss \
        --without-pulse \
        --without-udev \
        --without-usb \
        --without-v4l2 \
        --disable-winedbg \
        --without-cms \
        --without-gstreamer \
        --without-gsm \
        --without-gphoto \
        --without-sane \
        --with-mingw \
        --with-png \
        --with-sdl \
        --without-krb5 \
        --without-vkd3d \
        --without-vulkan \
        --disable-vulkan_1 \
        --disable-winevulkan \
        --without-x
popd

echo "Build wine32on64-${CROSS_OVER_VERSION}"
pushd ${BUILDROOT}/wine32on64-${CROSS_OVER_VERSION}
make -k -j$(sysctl -n hw.activecpu 2>/dev/null)
popd


############ Install wine ##############

echo "Install wine32on64-${CROSS_OVER_VERSION}"
pushd ${BUILDROOT}/wine32on64-${CROSS_OVER_VERSION}
make install-lib DESTDIR="${INSTALLROOT}/${WINE_INSTALLATION}"
popd

echo "Install wine64-${CROSS_OVER_VERSION}"
pushd ${BUILDROOT}/wine64-${CROSS_OVER_VERSION}
make install-lib DESTDIR="${INSTALLROOT}/${WINE_INSTALLATION}"
popd


############ Bundle and Upload Deliverable ##############

echo "Tar Wine"
pushd ${INSTALLROOT}
tar -czvf ${WINE_INSTALLATION}.tar.gz ${WINE_INSTALLATION}
popd

echo "Upload Wine"
mkdir -p ${PACKAGE_UPLOAD}
cp ${INSTALLROOT}/${WINE_INSTALLATION}.tar.gz ${PACKAGE_UPLOAD}/
