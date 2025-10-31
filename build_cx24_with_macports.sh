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

# directories / files inside the downloaded tar file directory structure
export WINE_CONFIGURE=$GITHUB_WORKSPACE/wine/configure

# build directories
export BUILDROOT=$GITHUB_WORKSPACE/build

# target directory for installation
export INSTALLROOT=$GITHUB_WORKSPACE/install

# artifact name
export WINE_INSTALLATION=winecx24

# Need to ensure port actually exists
if ! command -v "/opt/local/bin/port" &> /dev/null
then
    echo "</opt/local/bin/port> could not be found"
    echo "A MacPorts installation is required"
    exit
fi

# Manually configure $PATH
export PATH="/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Library/Apple/usr/bin"


#begingroup "Installing dependencies build"
#sudo port install bison ccache gettext mingw-w64 pkgconfig
#endgroup


#begingroup "Installing dependencies libraries"
#sudo port install freetype gnutls-devel gettext-runtime libpcap libsdl2 moltenvk-latest
#endgroup


export CC="clang"
export CXX="${CC}++"
export i386_CC="i686-w64-mingw32-gcc"
export x86_64_CC="x86_64-w64-mingw32-gcc"
export CPATH="/opt/local/include"
export LIBRARY_PATH="/opt/local/lib"
export MACOSX_DEPLOYMENT_TARGET="10.15"
export OPTFLAGS="-O2"
export CFLAGS="${OPTFLAGS} -Wno-deprecated-declarations -Wno-format"
# gcc14.1 now sets -Werror-incompatible-pointer-types
export CROSSCFLAGS="${OPTFLAGS} -Wno-incompatible-pointer-types"
export LDFLAGS="-Wl,-ld_classic -Wl,-headerpad_max_install_names -Wl,-rpath,@loader_path/../../ -Wl,-rpath,/opt/local/lib"

export ac_cv_lib_soname_vulkan=""


if [[ ! -d "${GITHUB_WORKSPACE}/wine" ]]; then
    git clone --branch crossover-24.0.7-fixup --depth=1 https://github.com/Gcenx/wine.git
fi


if [[ -d "${GITHUB_WORKSPACE}/build" ]]; then
    rm -rf ${GITHUB_WORKSPACE}/build
fi


begingroup "Configure winecx24"
mkdir -p ${BUILDROOT}
pushd ${BUILDROOT}
${WINE_CONFIGURE} \
    --prefix= \
    --disable-tests \
    --disable-winedbg \
    --enable-win64 \
    --enable-archs=i386,x86_64 \
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
    --with-opencl \
    --without-opengl \
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
    --without-wayland \
    --without-x
popd
endgroup


begingroup "Build winecx24"
pushd ${BUILDROOT}
make -j$(sysctl -n hw.ncpu 2>/dev/null)
popd
endgroup


begingroup "Install winecx24"
pushd ${BUILDROOT}
make install-image DESTDIR="${INSTALLROOT}/${WINE_INSTALLATION}"
popd
endgroup
