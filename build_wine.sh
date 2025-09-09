#!/usr/bin/env bash

########################################################################
##
## A script for Wine compilation.
## By default it uses two Ubuntu bootstraps (x32 and x64), which it enters
## with bubblewrap (root rights are not required).
##
## This script requires: git, wget, autoconf, xz, bubblewrap
##
## You can change the environment variables below to your desired values.
##
########################################################################

# Prevent launching as root
if [ $EUID = 0 ] && [ -z "$ALLOW_ROOT" ]; then
	echo "Do not run this script as root!"
	echo
	echo "If you really need to run it as root and you know what you are doing,"
	echo "set the ALLOW_ROOT environment variable."

	exit 1
fi

# Read current build config. from a different file
set -a
source "$(pwd)/build-version.cfg"
set +a

## -------------------------------------------------------
## 					Wine-Builds settings
## -------------------------------------------------------

# Wine version to compile.
# You can set it to "latest" to compile the latest available version.
# You can also set it to "git" to compile the latest git revision.
#
# This variable affects only vanilla and staging branches. Other branches
# use their own versions.
export WINE_VERSION="${WINE_VERSION:-latest}"

# Available branches: vanilla, staging, proton, staging-tkg, staging-tkg-ntsync
export WINE_BRANCH="${WINE_BRANCH:-staging}"

# Keeping track of the releases versions
export RELEASE_VERSION="${RELEASE_VERSION:-1}"

# Available proton branches: proton_3.7, proton_3.16, proton_4.2, proton_4.11
# proton_5.0, proton_5.13, experimental_5.13, proton_6.3, experimental_6.3
# proton_7.0, experimental_7.0, proton_8.0, experimental_8.0, experimental_9.0
# bleeding-edge
# Leave empty to use the default branch.
export PROTON_BRANCH="${PROTON_BRANCH:-proton_9.0}"

# Sometimes Wine and Staging versions don't match (for example, 5.15.2).
# Leave this empty to use Staging version that matches the Wine version.
export STAGING_VERSION="${STAGING_VERSION:-}"

# Specify custom arguments for the Staging's patchinstall.sh script.
# For example, if you want to disable ntdll-NtAlertThreadByThreadId
# patchset, but apply all other patches, then set this variable to
# "--all -W ntdll-NtAlertThreadByThreadId"
# Leave empty to apply all Staging patches
export STAGING_ARGS="${STAGING_ARGS:-}"

# Make 64-bit Wine builds with the new WoW64 mode (32-on-64)
export EXPERIMENTAL_WOW64="${EXPERIMENTAL_WOW64:-false}"

# Set this to a path to your Wine source code (for example, /home/username/wine-custom-src).
# This is useful if you already have the Wine source code somewhere on your
# storage and you want to compile it.
#
# You can also set this to a GitHub clone url instead of a local path.
#
# If you don't want to compile a custom Wine source code, then just leave this
# variable empty.
export CUSTOM_SRC_PATH=""

# Set to true to download and prepare the source code, but do not compile it.
# If this variable is set to true, root rights are not required.
export DO_NOT_COMPILE="false"

# Set to true to use ccache to speed up subsequent compilations.
# First compilation will be a little longer, but subsequent compilations
# will be significantly faster (especially if you use a fast storage like SSD).
#
# Note that ccache requires additional storage space.
# By default it has a 5 GB limit for its cache size.
#
# Make sure that ccache is installed before enabling this.
export USE_CCACHE="${USE_CCACHE:-false}"

# A temporary directory where the Wine source code will be stored.
# Do not set this variable to an existing non-empty directory!
# This directory is removed and recreated on each script run.
export BUILD_DIR="${HOME}"/build_wine
export scriptdir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

## ------------------------------------------------------------
## 						BOOTSTRAPS SETUP
## ------------------------------------------------------------

# Change these paths to where your Ubuntu bootstraps reside
export BOOTSTRAP_X64=/opt/chroots/focal_chroot
export BOOTSTRAP_PATH="$BOOTSTRAP_X64"

_bwrap () {
    bwrap --ro-bind "${BOOTSTRAP_PATH}" / --dev /dev --ro-bind /sys /sys \
		  --proc /proc --tmpfs /tmp --tmpfs /home --tmpfs /run --tmpfs /var \
		  --tmpfs /mnt --tmpfs /media --bind "${BUILD_DIR}" "${BUILD_DIR}" \
		  --bind-try "${XDG_CACHE_HOME}"/ccache "${XDG_CACHE_HOME}"/ccache \
		  --bind-try "${HOME}"/.ccache "${HOME}"/.ccache \
		  --setenv PATH "/usr/local/llvm-mingw/bin:/bin:/sbin:/usr/bin:/usr/sbin" \
		  --setenv LC_ALL en_US.UTF-8 \
		  --setenv LANGUAGE en_US.UTF-8 \
		  "$@"
			
}

if [ ! -d "${BOOTSTRAP_X64}" ] ; then
	clear
	echo "Ubuntu Bootstrap is required for compilation!"
	exit 1
fi

if ! command -v git 1>/dev/null; then
	echo "Please install git and run the script again"
	exit 1
fi

if ! command -v autoconf 1>/dev/null; then
	echo "Please install autoconf and run the script again"
	exit 1
fi

if ! command -v wget 1>/dev/null; then
	echo "Please install wget and run the script again"
	exit 1
fi

if ! command -v xz 1>/dev/null; then
	echo "Please install xz and run the script again"
	exit 1
fi

## ------------------------------------------------------------
## 						COMPILER SETUP
## ------------------------------------------------------------

export CC="gcc"
export CXX="g++"

export CROSSCC_X32="i686-w64-mingw32-gcc"
export CROSSCXX_X32="i686-w64-mingw32-g++"
export CROSSCC_X64="x86_64-w64-mingw32-gcc"
export CROSSCXX_X64="x86_64-w64-mingw32-g++"

export CFLAGS="-march=nocona -mtune=core-avx2 -pipe -O2 \
               -fno-strict-aliasing -fwrapv -mfpmath=sse \
               -D_GNU_SOURCE -D_TIME_BITS=64 -D_FILE_OFFSET_BITS=64 \
               -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -DNDEBUG -D_NDEBUG"
export CROSSCFLAGS="${CFLAGS}"
export LDFLAGS="${CFLAGS} -Wl,-O1,--sort-common,--as-needed"
export CROSSLDFLAGS="${CFLAGS} -Wl,-O1,--sort-common,--as-needed,--file-alignment=4096"

## ------------------------------------------------------------
## 						CCACHE SETUP
## ------------------------------------------------------------

if [ "$USE_CCACHE" = "true" ]; then
	export CC="ccache ${CC}"
	export CXX="ccache ${CXX}"

	export i386_CC="ccache ${CROSSCC_X32}"
	export x86_64_CC="ccache ${CROSSCC_X64}"
	export CROSSCC="ccache ${CROSSCC}"
	export CROSSCC_X32="ccache ${CROSSCC_X32}"
	export CROSSCXX_X32="ccache ${CROSSCXX_X32}"
	export CROSSCC_X64="ccache ${CROSSCC_X64}"
	export CROSSCXX_X64="ccache ${CROSSCXX_X64}"

	if [ -z "${XDG_CACHE_HOME}" ]; then
		export XDG_CACHE_HOME="${HOME}"/.cache
	fi

	mkdir -p "${XDG_CACHE_HOME}"/ccache
	mkdir -p "${HOME}"/.ccache
fi

## ------------------------------------------------------------
## 						WINE SETUP
## ------------------------------------------------------------

# Replace the "latest" parameter with the actual latest Wine version
if [ "${WINE_VERSION}" = "latest" ] || [ -z "${WINE_VERSION}" ]; then
	WINE_VERSION="$(wget -q -O - "https://raw.githubusercontent.com/wine-mirror/wine/master/VERSION" | tail -c +14)"
fi

# Stable and Development versions have a different source code location
# Determine if the chosen version is stable or development
if [ "$(echo "$WINE_VERSION" | cut -d "." -f2 | cut -c1)" = "0" ]; then
	WINE_URL_VERSION=$(echo "$WINE_VERSION" | cut -d "." -f 1).0
else
	WINE_URL_VERSION=$(echo "$WINE_VERSION" | cut --d "." -f 1).x
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}" || exit 1

echo
echo "Downloading the source code and patches"
echo "Preparing Wine for compilation"
echo

if [ -n "${CUSTOM_SRC_PATH}" ]; then
	is_url="$(echo "${CUSTOM_SRC_PATH}" | head -c 6)"

	if [ "${is_url}" = "git://" ] || [ "${is_url}" = "https:" ]; then
		git clone "${CUSTOM_SRC_PATH}" wine
	else
		if [ ! -f "${CUSTOM_SRC_PATH}"/configure ]; then
			echo "CUSTOM_SRC_PATH is set to an incorrect or non-existent directory!"
			echo "Please make sure to use a directory with the correct Wine source code."
			exit 1
		fi

		cp -r "${CUSTOM_SRC_PATH}" wine
	fi

	WINE_VERSION="$(cat wine/VERSION | tail -c +14)"
	BUILD_NAME="${WINE_VERSION}"-custom
elif [ "$WINE_BRANCH" = "staging-tkg" ] || [ "$WINE_BRANCH" = "staging-tkg-ntsync" ]; then
	if [ "$WINE_BRANCH" = "staging-tkg" ] && [ "${EXPERIMENTAL_WOW64}" = "true" ]; then
		git clone https://github.com/Kron4ek/wine-tkg wine -b wow64
	else
		if [ "$WINE_BRANCH" = "staging-tkg" ]; then
			git clone https://github.com/Kron4ek/wine-tkg wine
		else
			git clone https://github.com/Kron4ek/wine-tkg wine -b ntsync
		fi
	fi

	# Automate getting commit hash for all branches from WINE_VERSION to build specific versions
	cd wine || exit 1
	WINE_COMMIT=$(git log --pretty=format:"%H %s" | grep -F "Update to $WINE_VERSION" | head -n1 | awk '{print $1}')
	
	# Fail if commit isn't found in some extra branch (ntsync/wow64)
	if [ -z "$WINE_COMMIT" ]; then
    	echo "No commit found with WINE_VERSION: $WINE_VERSION, exiting.."
    	exit 1
	fi
	
	git checkout "$WINE_COMMIT"
	cd .. || exit 1

	WINE_VERSION="$(cat wine/VERSION | tail -c +14)"
	BUILD_NAME="spritz-$WINE_VERSION-$RELEASE_VERSION-$WINE_BRANCH-aagl"
elif [ "$WINE_BRANCH" = "proton" ]; then
	if [ -z "${PROTON_BRANCH}" ]; then
		git clone https://github.com/ValveSoftware/wine
	else
		git clone https://github.com/ValveSoftware/wine -b "${PROTON_BRANCH}"
	fi

	WINE_VERSION="$(cat wine/VERSION | tail -c +14)-$(git -C wine rev-parse --short HEAD)"
	if [[ "${PROTON_BRANCH}" == "experimental_"* ]] || [ "${PROTON_BRANCH}" = "bleeding-edge" ]; then
		BUILD_NAME=proton-exp-"${WINE_VERSION}"
	else
		BUILD_NAME=proton-"${WINE_VERSION}"
	fi
else
	if [ "${WINE_VERSION}" = "git" ]; then
		git clone https://gitlab.winehq.org/wine/wine.git wine
		BUILD_NAME="${WINE_VERSION}-$(git -C wine rev-parse --short HEAD)"
	else
		BUILD_NAME="${WINE_VERSION}"

		wget -q --show-progress "https://dl.winehq.org/wine/source/${WINE_URL_VERSION}/wine-${WINE_VERSION}.tar.xz"

		tar xf "wine-${WINE_VERSION}.tar.xz"
		mv "wine-${WINE_VERSION}" wine
	fi

	if [ "${WINE_BRANCH}" = "staging" ]; then
		if [ "${WINE_VERSION}" = "git" ]; then
			git clone https://github.com/wine-staging/wine-staging wine-staging-"${WINE_VERSION}"

			upstream_commit="$(cat wine-staging-"${WINE_VERSION}"/staging/upstream-commit | head -c 7)"
			git -C wine checkout "${upstream_commit}"
			BUILD_NAME="${WINE_VERSION}-${upstream_commit}-staging"
		else
			if [ -n "${STAGING_VERSION}" ]; then
				WINE_VERSION="${STAGING_VERSION}"
			fi

			BUILD_NAME="${WINE_VERSION}"-staging

			wget -q --show-progress "https://github.com/wine-staging/wine-staging/archive/v${WINE_VERSION}.tar.gz"
			tar xf v"${WINE_VERSION}".tar.gz

			if [ ! -f v"${WINE_VERSION}".tar.gz ]; then
				git clone https://github.com/wine-staging/wine-staging wine-staging-"${WINE_VERSION}"
			fi
		fi

		BUILD_NAME="spritz-$WINE_VERSION-$RELEASE_VERSION-tkg-aagl"

		if [ -f wine-staging-"${WINE_VERSION}"/patches/patchinstall.sh ]; then
			staging_patcher=("${BUILD_DIR}"/wine-staging-"${WINE_VERSION}"/patches/patchinstall.sh
							DESTDIR="${BUILD_DIR}"/wine)
		else
			staging_patcher=("${BUILD_DIR}"/wine-staging-"${WINE_VERSION}"/staging/patchinstall.py)
		fi

		cd wine || exit 1
		if [ -n "${STAGING_ARGS}" ]; then
			_bwrap "${staging_patcher[@]}" ${STAGING_ARGS}
		else
			_bwrap "${staging_patcher[@]}" --all
		fi

		if [ $? -ne 0 ]; then
			echo
			echo "Wine-Staging patches were not applied correctly!"
			exit 1
		fi

		cd "${BUILD_DIR}" || exit 1
	fi
fi

## ------------------------------------------------------------
## 						BUILD SETUP
## ------------------------------------------------------------

export WINE_BUILD_OPTIONS=(
        --prefix="${BUILD_DIR}/${BUILD_OUT_TMP_DIR}"
        --disable-tests
        --disable-winemenubuilder
        --disable-win16
        --with-x
        --with-gstreamer
        --with-wayland
        --without-oss
        --without-coreaudio
        --without-cups
        --without-sane
        --without-gphoto
        --without-pcsclite
        --without-pcap
        --without-capi
        --without-v4l2
        --without-netapi
        --disable-msv1_0
    )

# Options appended only to the 64bit build
if [ "${EXPERIMENTAL_WOW64}" = "true" ]; then
	WINE_64_BUILD_OPTIONS=(
		--enable-archs="x86_64,i386"
		--libdir="${BUILD_DIR}"/"${BUILD_OUT_TMP_DIR}"/lib
	)
else
	WINE_64_BUILD_OPTIONS=(
		--enable-win64
		--libdir="${BUILD_DIR}"/"${BUILD_OUT_TMP_DIR}"/lib
	)
fi

# Options appended only to the 32bit build
WINE_32_BUILD_OPTIONS=(
	--libdir="${BUILD_DIR}"/"${BUILD_OUT_TMP_DIR}"/lib
    --with-wine64="${BUILD_DIR}"/build64
)

if [ ! -d wine ]; then
	clear
	echo "No Wine source code found!"
	echo "Make sure that the correct Wine version is specified."
	exit 1
fi

BUILD_OUT_TMP_DIR=wine-"$BUILD_NAME"-amd64
cd wine || exit 1

# Applying custom patches
patches_dir="$scriptdir/patches"
for i in $(find "$patches_dir" -type f -regex ".*\.patch" | sort); do
    [ ! -f "$i" ] && continue
    echo "Applying custom patch '$i'" 
    patch -Np1 -i "$i" >> $scriptdir/patches.log || Error "Applying patch '$i' failed, read at: $scriptdir/patches.log"
done

## ------------------------------------------------------------
## 						WINE BUILDING
## ------------------------------------------------------------

dlls/winevulkan/make_vulkan
tools/make_requests
tools/make_specfiles
_bwrap autoreconf -f

cd "${BUILD_DIR}" || exit 1

if [ "${DO_NOT_COMPILE}" = "true" ]; then
	clear
	echo "DO_NOT_COMPILE is set to true"
	echo "Force exiting"
	exit
fi

export PKG_CONFIG_LIBDIR=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig
export PKG_CONFIG_PATH=$PKG_CONFIG_LIBDIR
export x86_64_CC="${CROSSCC_X64}"
export CROSSCC="${CROSSCC_X64}"

rm -rf "${BUILD_DIR}"/build64 || true
mkdir "${BUILD_DIR}"/build64
cd "${BUILD_DIR}"/build64 || exit 1
_bwrap "${BUILD_DIR}"/wine/configure \
			"${WINE_BUILD_OPTIONS[@]}" \
			"${WINE_64_BUILD_OPTIONS[@]}"

_bwrap make -j$(($(nproc) + 1)) || Error "Wine 64-bit build failed, check logs"

# Only build Wine-32 if not WoW64
if ! [ "${EXPERIMENTAL_WOW64}" = "true" ]; then

	export PKG_CONFIG_LIBDIR=/usr/lib/i386-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/lib/i386-linux-gnu/pkgconfig:/usr/local/i386/lib/i386-linux-gnu/pkgconfig:${LLVM_MINGW_PATH}/i686-w64-mingw32/lib/pkgconfig
	export PKG_CONFIG_PATH=$PKG_CONFIG_LIBDIR
	export i386_CC="${CROSSCC_X32}"
	export CROSSCC="${CROSSCC_X32}"

	rm -rf "${BUILD_DIR}"/build32 || true
	mkdir "${BUILD_DIR}"/build32
	cd "${BUILD_DIR}"/build32 || exit 1
	_bwrap "${BUILD_DIR}"/wine/configure \
				"${WINE_BUILD_OPTIONS[@]}" \
				"${WINE_32_BUILD_OPTIONS[@]}"

	_bwrap make -j$(($(nproc) + 1)) || Error "Wine 32-bit build failed, check logs"
fi

echo
echo "Compilation complete"
echo "Creating and compressing archives..."

cd "${BUILD_DIR}" || exit 1

if touch "${scriptdir}"/write_test; then
	rm -f "${scriptdir}"/write_test
	result_dir="${scriptdir}"
else
	result_dir="${HOME}"
fi

export XZ_OPT="-9"

if [ -d "$BUILD_DIR" ]; then

	if ! [ "${EXPERIMENTAL_WOW64}" = "true" ]; then
		echo "Packaging Wine-32..."
		cd "${BUILD_DIR}"/build32 || exit 1
		_bwrap make -j$(($(nproc) + 1)) \
		prefix="${BUILD_DIR}"/"${BUILD_OUT_TMP_DIR}" \
		libdir="${BUILD_DIR}"/"${BUILD_OUT_TMP_DIR}"/lib \
		dlldir="${BUILD_DIR}"/"${BUILD_OUT_TMP_DIR}"/lib/wine install-lib
	fi

	echo "Packaging Wine-64..."
	cd "${BUILD_DIR}"/build64 || exit 1
	_bwrap make -j$(($(nproc) + 1))  \
	prefix="${BUILD_DIR}"/"${BUILD_OUT_TMP_DIR}" \
	libdir="${BUILD_DIR}"/"${BUILD_OUT_TMP_DIR}"/lib \
	dlldir="${BUILD_DIR}"/"${BUILD_OUT_TMP_DIR}"/lib/wine install-lib

	echo "Stripping unneeded symbols from libraries..."
    find "${BUILD_DIR}/${BUILD_OUT_TMP_DIR}/lib/" \
		-type f '(' -iname '*.a' -o -iname '*.dll' -o -iname '*.so' -o -iname '*.sys' -o -iname '*.drv' -o -iname '*.exe' ')' \
		-print0 | xargs -0 strip -s 2>/dev/null || true
fi

build="${BUILD_OUT_TMP_DIR}"
cd "${BUILD_DIR}" || exit 1

if [ "${EXPERIMENTAL_WOW64}" = "true" ]; then
	mv "${build}" "${build}-wow64"
	build="${build}-wow64"	
fi

if [ -d "${build}" ]; then
	if [ -f wine/wine-tkg-config.txt ]; then
		cp wine/wine-tkg-config.txt "${build}"
	fi

	tar -Jcf "${build}".tar.xz "${build}"
	mv "${build}".tar.xz "${result_dir}"
fi


rm -rf "${BUILD_DIR}"

echo
echo "Done"
echo "The builds should be in ${result_dir}"
