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
    export CROSS_OVER_VERSION=22.1.1
    echo "CROSS_OVER_VERSION not set building crossover-wine-${CROSS_OVER_VERSION}"
fi

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

# Need to ensure port actually exists
if ! command -v "/opt/local/bin/port" &> /dev/null
then
    echo "</opt/local/bin/port> could not be found"
    echo "A macports installation is required"
    exit
fi

# Need CodeWeavers custom llvm toolchain for -mwine32 target
if ! command -v "/opt/opt/bin/clang" &> /dev/null; then
    begingroup "Fetching cx-llvm..."
    /usr/bin/curl -fsSLO "https://github.com/Gcenx/homebrew-wine/releases/download/cx-llvm-22.0.1/cx-llvm-22.0.1.big_sur.bottle.tar.gz" & curl_llvm_pid=$!
    endgroup


    begingroup "Installing cx-llvm"
    wait $curl_llvm_pid
    echo "Extracting..."
    sudo mkdir /opt/cx-llvm
    sudo tar -xpf "cx-llvm-22.0.1.big_sur.bottle.tar.gz" --strip-components=2 -C /opt/cx-llvm
    endgroup
fi


# Manually configure $PATH
export PATH="/opt/opt/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Library/Apple/usr/bin"


begingroup "Installing dependencies build"
sudo port install bison ccache gettext mingw-w64 pkgconfig
endgroup


begingroup "Installing dependencies libraries"
sudo port install freetype gettext-runtime gnutls moltenvk libpcap libsdl2
endgroup


export CC="ccache clang"
export CXX="${CC}++"
export CPATH=/opt/local/include
export LIBRARY_PATH=/opt/local/lib
export MACOSX_DEPLOYMENT_TARGET=10.14
export CROSSCFLAGS="-g -O2"
export CFLAGS="${CROSSCFLAGS} -Wno-deprecated-declarations -Wno-format"
export LDFLAGS="-Wl,-headerpad_max_install_names -Wl,-rpath,@loader_path/../../ -Wl,-rpath,/usr/local/lib -Wl,-rpath,/opt/local/lib -Wl,-rpath,/opt/X11/lib"

export ac_cv_lib_soname_MoltenVK="libMoltenVK.dylib"
export ac_cv_lib_soname_vulkan=""


if [[ ! -f ${CROSS_OVER_LOCAL_FILE}.tar.gz ]]; then
    begingroup "Downloading $CROSS_OVER_LOCAL_FILE"
    curl -o ${CROSS_OVER_LOCAL_FILE}.tar.gz ${CROSS_OVER_SOURCE_URL}
    endgroup
fi


begingroup "Extracting $CROSS_OVER_LOCAL_FILE"
if [[ -d "${GITHUB_WORKSPACE}/sources" ]]; then
    rm -rf ${GITHUB_WORKSPACE}/sources
fi
tar xf ${CROSS_OVER_LOCAL_FILE}.tar.gz
endgroup


+begingroup "Add distversion.h"
cp ${GITHUB_WORKSPACE}/distversion.h ${GITHUB_WORKSPACE}/sources/wine/include/distversion.h
endgroup


begingroup "Configure wine64-${CROSS_OVER_VERSION}"
mkdir -p ${BUILDROOT}/wine64-${CROSS_OVER_VERSION}
pushd ${BUILDROOT}/wine64-${CROSS_OVER_VERSION}
${WINE_CONFIGURE} \
    CROSSCC="ccache x86_64-w64-mingw32-gcc" \
    --prefix= \
    --disable-tests \
    --disable-winedbg \
    --enable-win64 \
    --without-alsa \
    --without-capi \
    --with-coreaudio \
    --with-cups \
    --without-dbus \
    --without-fontconfig \
    --with-freetype \
    --with-gettext \
    --without-gettextpo \
    --without-gphoto \
    --with-gnutls \
    --without-gssapi \
    --without-gstreamer \
    --without-inotify \
    --without-krb5 \
    --with-mingw \
    --without-netapi \
    --without-openal \
    --with-opencl \
    --with-opengl \
    --without-oss \
    --with-pcap \
    --with-pthread \
    --without-pulse \
    --without-sane \
    --with-sdl \
    --without-udev \
    --with-unwind \
    --without-usb \
    --without-v4l2 \
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
    CROSSCC="ccache i686-w64-mingw32-gcc" \
    --prefix= \
    --disable-loader \
    --disable-tests \
    --disable-winedbg \
    --enable-win32on64 \
    --without-alsa \
    --without-capi \
    --with-coreaudio \
    --with-cups \
    --without-dbus \
    --without-fontconfig \
    --with-freetype \
    --with-gettext \
    --without-gettextpo \
    --without-gphoto \
    --with-gnutls \
    --without-gssapi \
    --without-gstreamer \
    --without-inotify \
    --without-krb5 \
    --with-mingw \
    --without-netapi \
    --without-openal \
    --with-opencl \
    --with-opengl \
    --without-oss \
    --with-pcap \
    --with-pthread \
    --without-pulse \
    --without-sane \
    --with-sdl \
    --without-udev \
    --with-unwind \
    --without-usb \
    --without-v4l2 \
    --with-vulkan \
    --with-wine64=${BUILDROOT}/wine64-${CROSS_OVER_VERSION} \
    --without-x
popd
endgroup


begingroup "Build wine32on64-${CROSS_OVER_VERSION}"
pushd ${BUILDROOT}/wine32on64-${CROSS_OVER_VERSION}
make -j$(sysctl -n hw.activecpu 2>/dev/null)
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
