##
# Author        Tim Stahlhut stahta01@gmail.com
# Created:      2021-09-09
# Last edited:  2021-09-17
# Purpose:      Builds an local GCC-ADA that uses a different C Runtime (CRT)
# Requires:     GCC with Ada
# No copyright; public domain
####

set -e            # Abort script on error
set -o pipefail   # Abort on error in pipe

##
# Start of helper functions #
apply_patch_with_msg() {
  for _patch in "$@"
  do
    if patch --dry-run -Nbp1 -i "${STARTING_FOLDER}/${_patch}" > /dev/null 2>&1 ; then
      echo "Applying ${_patch}"
      patch -Nbp1 -i "${STARTING_FOLDER}/${_patch}"
    elif patch --dry-run -Rbp1 -i "${STARTING_FOLDER}/${_patch}" > /dev/null 2>&1 ; then
      echo "Skipping ${_patch} because it likely was already applied"
    else
      echo "Skipping ${_patch} because it likely will fail"
    fi
  done
}
extract_gcc() {
    if [ ! -d  "$GCC_VERSION" ]; then
        echo "Extracting $REAL_GCC_VERSION.tar.xz into $GCC_VERSION"
        mkdir -p "$GCC_VERSION"
        tar --directory=$GCC_VERSION --strip-components=1 -xf "$REAL_GCC_VERSION.tar.xz"
    fi
}
extract_to_gcc_folder() {
    local tarfile="$1"
    local subfolder="$(echo "$tarfile" | sed 's/-.*$//')"
    if [ ! -d  "$GCC_VERSION/$subfolder" ]; then
        echo "Extracting ${tarfile} to $GCC_VERSION/$subfolder"
        mkdir -p "$GCC_VERSION/$subfolder"
        tar -x --strip-components=1 -f "$tarfile" -C "$GCC_VERSION/$subfolder"
    fi
}
extract() {
    local tarfile="$1"
    local extracted="$(echo "$tarfile" | sed 's/\.tar.*$//')"
    if [ ! -d  "$extracted" ]; then
        echo "Extracting ${tarfile}"
        tar -xf $tarfile
    fi
}
# End of helper functions #
####

# Step A0: Set file versions
REAL_GCC_VERSION=gcc-10.3.0
GCC_VERSION="src-$REAL_GCC_VERSION"
#ISL_VERSION=isl-0.22

MINGW64_CRT_GIT_COMMIT='f5ac9206e576c0968c84aaaee4242072775e9b32'
MANIFEST_GIT_TAG="release-6_4"

# Step A1: Save STARTING_FOLDER and set other settings
STARTING_FOLDER=$PWD
echo "Step A1a: path is $PATH" > ${STARTING_FOLDER}/pathchange.log

HOST_PREFIX=/mingw64
TARGET_BOOT_PREFIX="$HOST_PREFIX/local/boot/ucrt64"
TARGET_TRIPLET=x86_64-w64-mingw32
PARALLEL_MAKE=-j1 # Use j1 for old CPUs/Computers

MINGW64_CRT_REPO=mingw-w64
MINGW64_CRT_GIT_URL=git://github.com/mirror/${MINGW64_CRT_REPO}.git
MINGW64_CRT_BRANCH=master
MINGW64_CRT_FOLDER=mingw-w64-git

MANIFEST_BRANCH="master"
MANIFEST_FOLDER="manifest-git"
MANIFEST_GIT_URL="git://sourceware.org/git/cygwin-apps/windows-default-manifest.git"

COMMON_CONFIGURATION_OPTIONS="--disable-multilib --disable-rpath --disable-werror --disable-threads --disable-lto --disable-nls"

DO_BOOT_MINGW64_CRT_CONFIG=1

# Step A3: Download required files
wget -nc https://ftp.gnu.org/gnu/gcc/$REAL_GCC_VERSION/$REAL_GCC_VERSION.tar.xz
#wget -nc http://isl.gforge.inria.fr/$ISL_VERSION.tar.bz2
if [ ! -d $MINGW64_CRT_FOLDER ]; then
    git clone $MINGW64_CRT_GIT_URL $MINGW64_CRT_FOLDER
fi
(
    cd $MINGW64_CRT_FOLDER
    git checkout $MINGW64_CRT_BRANCH
    git reset --hard $MINGW64_CRT_GIT_COMMIT
)

if [ ! -d $MANIFEST_FOLDER ]; then
    git clone $MANIFEST_GIT_URL $MANIFEST_FOLDER
fi
(
    cd $MANIFEST_FOLDER
    git checkout $MANIFEST_BRANCH
    git reset --hard $MANIFEST_GIT_TAG
)

# Step A4: Extract files
extract_gcc
#extract_to_gcc_folder       $ISL_VERSION.tar.bz2

# Step A5: Patch files
echo "Step A5: Starting Patch Operations" > ${STARTING_FOLDER}/patch.log
echo "Step A5: Starting Patch Operations" > ${STARTING_FOLDER}/build-time.log
date --rfc-3339=seconds >> ${STARTING_FOLDER}/build-time.log

cd ${STARTING_FOLDER}/${GCC_VERSION}
apply_patch_with_msg 0002-Relocate-libintl.patch 2>&1 | tee --append ../patch.log
apply_patch_with_msg 0003-Windows-Follow-Posix-dir-exists-semantics-more-close.patch 2>&1 | tee --append ../patch.log
apply_patch_with_msg 0004-Windows-Use-not-in-progpath-and-leave-case-as-is.patch 2>&1 | tee --append ../patch.log
apply_patch_with_msg 0005-Windows-Don-t-ignore-native-system-header-dir.patch 2>&1 | tee --append ../patch.log
apply_patch_with_msg 0006-Windows-New-feature-to-allow-overriding.patch 2>&1 | tee --append ../patch.log
#apply_patch_with_msg 0007-Build-EXTRA_GNATTOOLS-for-Ada.patch 2>&1 | tee --append ../patch.log
apply_patch_with_msg 0011-Enable-shared-gnat-implib.patch  2>&1 | tee --append ../patch.log
apply_patch_with_msg 0012-Handle-spaces-in-path-for-default-manifest.patch 2>&1 | tee --append ../patch.log
apply_patch_with_msg 0021-gcc-config-i386-mingw32.h-Ensure-lmsvcrt-precede-lke.patch 2>&1 | tee --append ../patch.log
apply_patch_with_msg 0130-libstdc++-in-out.patch 2>&1 | tee --append ../patch.log
apply_patch_with_msg 0160-libbacktrace-seh.patch 2>&1 | tee --append ../patch.log

# Disable self tests that are failing under msys2 mingw for a reason I can not figure out
sed -i 's|SELFTEST_TARGETS = @selftest_languages@|SELFTEST_TARGETS =|'  gcc/Makefile.in
#sed -i 's|DEVNULL=$(if $(findstring mingw,$(build)),nul,/dev/null)|DEVNULL=/dev/null|g' gcc/Makefile.in

# replace gnatmake with full path of gnatmake safest way I found to bootstrap Ada
sed -i 's| gnatmake | /mingw64/bin/gnatmake.exe |g' gcc/ada/Make-generated.in

sed -i 's|(cd ./bldtools/oscons ; gnatmake -q xoscons)|(cd ./bldtools/oscons ; $(GNATMAKE) -q xoscons)|g' gcc/ada/gcc-interface/Makefile.in

#
###

#echo "Step B1a: Delete $TARGET_BOOT_PREFIX folder" > ${STARTING_FOLDER}/build-boot-${REAL_GCC_VERSION}.log
#rm -fr "$TARGET_BOOT_PREFIX"
#mkdir -p "$TARGET_BOOT_PREFIX"
#
#echo "Step B1b: Install MinGW64 Headers" > ${STARTING_FOLDER}/build-boot-headers-${TARGET_TRIPLET}.log && \
#cd ${STARTING_FOLDER} && \
#mkdir -p build-boot-headers-${TARGET_TRIPLET} && cd build-boot-headers-${TARGET_TRIPLET} && \
#CC="${HOST_PREFIX}/bin/gcc.exe -mcrtdll=ucrt" \
#CXX="${HOST_PREFIX}/bin/g++.exe -mcrtdll=ucrt" \
#GNATBIND="${HOST_PREFIX}/bin/gnatbind.exe" \
#GNATMAKE="${HOST_PREFIX}/bin/gnatmake.exe" \
#PATH="${HOST_PREFIX}/bin:$PATH" \
#CPPFLAGS="-D__USE_MINGW_ANSI_STDIO=1 -I$HOST_PREFIX/${TARGET_TRIPLET}/include" \
#CFLAGS="-march=x86-64 -mtune=generic -O2 -pipe" \
#CXXFLAGS="-march=x86-64 -mtune=generic -O2 -pipe" \
#LDFLAGS="-pipe -L$TARGET_BOOT_PREFIX/${TARGET_TRIPLET}/lib -L$TARGET_BOOT_PREFIX/lib -L$HOST_PREFIX/${TARGET_TRIPLET}/lib -L$HOST_PREFIX/lib" \
#../${MINGW64_CRT_FOLDER}/mingw-w64-headers/configure \
#  --build=x86_64-w64-mingw32 \
#  --host=x86_64-w64-mingw32 \
#  --target=${TARGET_TRIPLET} \
#  --prefix=$TARGET_BOOT_PREFIX/${TARGET_TRIPLET} \
#  --enable-sdk=all \
#  --with-default-win32-winnt=0x601 \
#  --with-default-msvcrt=ucrt \
#  --enable-idl \
#  --without-widl  2>&1 | tee --append ../build-boot-headers-${TARGET_TRIPLET}.log && \
#cd ${STARTING_FOLDER}/build-boot-headers-${TARGET_TRIPLET} && \
#make install 2>&1 | tee --append ../build-boot-headers-${TARGET_TRIPLET}.log || exit 1
#
#echo "Step B2a: Configure Full GCC" > ${STARTING_FOLDER}/build-boot-${REAL_GCC_VERSION}.log && \
# rm -fr ${STARTING_FOLDER}/build-boot-${REAL_GCC_VERSION} && \
#mkdir -p ${STARTING_FOLDER}/build-boot-${REAL_GCC_VERSION} && cd ${STARTING_FOLDER}/build-boot-${REAL_GCC_VERSION} && \
#CC="${HOST_PREFIX}/bin/gcc.exe -mcrtdll=ucrt -D_UCRT" \
#CXX="${HOST_PREFIX}/bin/g++.exe -mcrtdll=ucrt -D_UCRT" \
#GNATBIND="${HOST_PREFIX}/bin/gnatbind.exe" \
#GNATMAKE="${HOST_PREFIX}/bin/gnatmake.exe" \
#PATH="${HOST_PREFIX}/bin:$PATH" \
#CFLAGS="-march=x86-64 -mtune=generic -O2 -pipe" \
#CXXFLAGS="-march=x86-64 -mtune=generic -O2 -pipe" \
#LDFLAGS="-pipe -L${TARGET_BOOT_PREFIX}/${TARGET_TRIPLET}/lib" \
#../$GCC_VERSION/configure \
#  $COMMON_CONFIGURATION_OPTIONS \
#  --prefix=$TARGET_BOOT_PREFIX \
#  --libexecdir=${TARGET_BOOT_PREFIX}/lib \
#  --with-native-system-header-dir=${TARGET_BOOT_PREFIX}/${TARGET_TRIPLET}/include \
#  --target=$TARGET_TRIPLET \
#  --with-{gmp,mpfr,mpc,zlib}=$HOST_PREFIX \
#  --without-isl \
#  --without-libiconv \
#  --enable-languages=c,c++,ada \
#  --enable-shared --enable-static \
#  --enable-libada \
#  --disable-bootstrap \
#  --disable-checking \
#  --disable-win32-registry \
#  --disable-symvers \
#  --with-arch=x86-64 --with-tune=generic \
#  --with-gnu-as --with-gnu-ld \
#  --disable-libstdcxx-pch \
#  --disable-libstdcxx-debug 2>&1 | tee --append ../build-boot-${REAL_GCC_VERSION}.log || exit 1
#echo "Step B2b: Build and Install boot GCC" >> ${STARTING_FOLDER}/build-boot-${REAL_GCC_VERSION}.log && \
#cd ${STARTING_FOLDER}/build-boot-${REAL_GCC_VERSION} && \
#make $PARALLEL_MAKE all-gcc 2>&1 | tee --append ../build-boot-${REAL_GCC_VERSION}.log && \
#make install-gcc 2>&1 | tee --append ../build-boot-${REAL_GCC_VERSION}.log || exit 1

if [ $DO_BOOT_MINGW64_CRT_CONFIG -eq 1 ]; then
  echo "Step B3a: Configure MinGW64 CRT" > ${STARTING_FOLDER}/build-boot-crt-${TARGET_TRIPLET}.log && \
  cd ${STARTING_FOLDER} && \
  mkdir -p build-boot-crt-${TARGET_TRIPLET} && cd build-boot-crt-${TARGET_TRIPLET} && \
  CC="${HOST_PREFIX}/bin/gcc.exe -mcrtdll=ucrt" \
  CXX="${HOST_PREFIX}/bin/g++.exe -mcrtdll=ucrt" \
  GNATBIND="${HOST_PREFIX}/bin/gnatbind.exe" \
  GNATMAKE="${HOST_PREFIX}/bin/gnatmake.exe" \
  PATH="${HOST_PREFIX}/bin:$PATH" \
  CFLAGS="-march=x86-64 -mtune=generic -O2 -pipe" \
  CXXFLAGS="-march=x86-64 -mtune=generic -O2 -pipe" \
  LDFLAGS="-pipe" \
  ../${MINGW64_CRT_FOLDER}/mingw-w64-crt/configure \
    --build=x86_64-w64-mingw32 \
    --host=x86_64-w64-mingw32 \
    --target=${TARGET_TRIPLET} \
    --prefix=$TARGET_BOOT_PREFIX/${TARGET_TRIPLET} \
    --with-default-msvcrt=ucrt \
    --with-sysroot=$TARGET_BOOT_PREFIX/${TARGET_TRIPLET} \
    --enable-wildcard \
    --disable-dependency-tracking \
    --disable-lib32 --enable-lib64 2>&1 | tee --append ../build-boot-crt-${TARGET_TRIPLET}.log || exit 1
fi
echo "Step B3b: Build and Install MinGW64 CRT" >> ${STARTING_FOLDER}/build-boot-crt-${TARGET_TRIPLET}.log && \
cd ${STARTING_FOLDER}/build-boot-crt-${TARGET_TRIPLET} && \
make 2>&1 | tee --append ../build-boot-crt-${TARGET_TRIPLET}.log && \
make install-strip 2>&1 | tee --append ../build-boot-crt-${TARGET_TRIPLET}.log || exit 1

echo "Step B5a. Configure windows-default-manifest" >> ${STARTING_FOLDER}/build-boot-manifest.log && \
  cd ${STARTING_FOLDER} && \
  [[ -d ${STARTING_FOLDER}/build-boot-manifest ]] && rm -rf ${STARTING_FOLDER}/build-boot-manifest
  cp -rf ${STARTING_FOLDER}/$MANIFEST_FOLDER ${STARTING_FOLDER}/build-boot-manifest
  cd ${STARTING_FOLDER}/build-boot-manifest
  CC="${TARGET_BOOT_PREFIX}/bin/gcc.exe" \
  CXX="${TARGET_BOOT_PREFIX}/bin/g++.exe" \
  PATH="${TARGET_BOOT_PREFIX}/bin:${HOST_PREFIX}/bin:$PATH" \
  CPPFLAGS="-D__USE_MINGW_ANSI_STDIO=1 -I$HOST_PREFIX/${TARGET_TRIPLET}/include" \
  CFLAGS="-march=x86-64 -mtune=generic -O2 -pipe -fexceptions" \
  CXXFLAGS="-march=x86-64 -mtune=generic -O2 -pipe -fexceptions" \
  LDFLAGS="-pipe -L$TARGET_BOOT_PREFIX/${TARGET_TRIPLET}/lib -L$TARGET_BOOT_PREFIX/lib -L$HOST_PREFIX/${TARGET_TRIPLET}/lib -L$HOST_PREFIX/lib" \
  ./configure \
    --prefix=$TARGET_BOOT_PREFIX/${TARGET_TRIPLET} \
    --build=x86_64-w64-mingw32 \
    --host=x86_64-w64-mingw32 \
    --target=${TARGET_TRIPLET} 2>&1 | tee --append ../build-boot-manifest.log || exit 1
echo "Step B5b. Build and install windows-default-manifest" >> ${STARTING_FOLDER}/build-boot-manifest.log && \
cd ${STARTING_FOLDER}/build-boot-manifest && \
make $PARALLEL_MAKE 2>&1 | tee --append ../build-boot-manifest.log && \
make install 2>&1 | tee --append ../build-boot-manifest.log || exit 1

#echo "Step B6a: Build and Install target-libgcc" >> ${STARTING_FOLDER}/build-boot-${REAL_GCC_VERSION}.log && \
#cd ${STARTING_FOLDER}/build-boot-${REAL_GCC_VERSION} && \
#make $PARALLEL_MAKE all-target-libgcc 2>&1 | tee --append ../build-boot-${REAL_GCC_VERSION}.log && \
#make install-target-libgcc 2>&1 | tee --append ../build-boot-${REAL_GCC_VERSION}.log || exit 1
#
#echo "Step B6b: Build and Install target-libada" >> ${STARTING_FOLDER}/build-boot-${REAL_GCC_VERSION}.log && \
#cd ${STARTING_FOLDER}/build-boot-${REAL_GCC_VERSION} && \
#make $PARALLEL_MAKE all-target-libada 2>&1 | tee --append ../build-boot-${REAL_GCC_VERSION}.log && \
#make install-target-libada 2>&1 | tee --append ../build-boot-${REAL_GCC_VERSION}.log || exit 1
#
#echo "Step B6c: Build and Install gnattools" >> ${STARTING_FOLDER}/build-boot-${REAL_GCC_VERSION}.log && \
#cd ${STARTING_FOLDER}/build-boot-${REAL_GCC_VERSION} && \
#make $PARALLEL_MAKE all-gnattools 2>&1 | tee --append ../build-boot-${REAL_GCC_VERSION}.log && \
#make install-gnattools 2>&1 | tee --append ../build-boot-${REAL_GCC_VERSION}.log || exit 1


TARGET_INSTALL_PREFIX="$HOST_PREFIX/local/ucrt64"

echo "Step B6: Install MinGW64 Headers" > ${STARTING_FOLDER}/build-headers-${TARGET_TRIPLET}.log && \
cd ${STARTING_FOLDER} && \
mkdir -p build-headers-${TARGET_TRIPLET} && cd build-headers-${TARGET_TRIPLET} && \
CC="${TARGET_BOOT_PREFIX}/bin/gcc.exe" \
CXX="${TARGET_BOOT_PREFIX}/bin/g++.exe" \
GNATBIND="${TARGET_BOOT_PREFIX}/bin/gnatbind.exe" \
PATH="${TARGET_BOOT_PREFIX}/bin:$PATH" \
CPPFLAGS="-D__USE_MINGW_ANSI_STDIO=1" \
CFLAGS="-march=x86-64 -mtune=generic -O2 -pipe" \
CXXFLAGS="-march=x86-64 -mtune=generic -O2 -pipe" \
LDFLAGS="-pipe" \
../${MINGW64_CRT_FOLDER}/mingw-w64-headers/configure \
  --build=x86_64-w64-mingw32 \
  --host=x86_64-w64-mingw32 \
  --target=${TARGET_TRIPLET} \
  --prefix=$TARGET_INSTALL_PREFIX/${TARGET_TRIPLET} \
  --enable-sdk=all \
  --with-default-win32-winnt=0x601 \
  --with-default-msvcrt=ucrt \
  --enable-idl \
  --without-widl  2>&1 | tee --append ../build-headers-${TARGET_TRIPLET}.log && \
cd ${STARTING_FOLDER}/build-headers-${TARGET_TRIPLET} && \
make install 2>&1 | tee --append ../build-headers-${TARGET_TRIPLET}.log || exit 1

echo "Step B7a: Configure Full GCC" > ${STARTING_FOLDER}/build-${REAL_GCC_VERSION}.log && \
rm -fr ${STARTING_FOLDER}/build-${REAL_GCC_VERSION} && \
mkdir -p ${STARTING_FOLDER}/build-${REAL_GCC_VERSION} && cd ${STARTING_FOLDER}/build-${REAL_GCC_VERSION} && \
CC="${TARGET_BOOT_PREFIX}/bin/gcc.exe" \
CXX="${TARGET_BOOT_PREFIX}/bin/g++.exe" \
GNATBIND="${TARGET_BOOT_PREFIX}/bin/gnatbind.exe" \
GNATMAKE="${HOST_PREFIX}/bin/gnatmake.exe" \
PATH="${TARGET_BOOT_PREFIX}/bin:${TARGET_BOOT_PREFIX}/lib/gcc/x86_64-w64-mingw32/10.3.0:${HOST_PREFIX}/bin:$PATH" \
CFLAGS="-march=x86-64 -mtune=generic -O2 -pipe" \
CXXFLAGS="-march=x86-64 -mtune=generic -O2 -pipe" \
LDFLAGS="-pipe" \
../$GCC_VERSION/configure \
  $COMMON_CONFIGURATION_OPTIONS \
  --prefix=$TARGET_INSTALL_PREFIX \
  --libexecdir=${TARGET_INSTALL_PREFIX}/lib \
  --with-native-system-header-dir=${TARGET_INSTALL_PREFIX}/${TARGET_TRIPLET}/include \
  --target=$TARGET_TRIPLET \
  --with-{gmp,mpfr,mpc,zlib}=$HOST_PREFIX \
  --without-isl \
  --without-libiconv \
  --enable-languages=c,c++,ada \
  --enable-shared --enable-static \
  --enable-libada \
  --disable-bootstrap \
  --disable-checking \
  --disable-win32-registry \
  --disable-symvers \
  --with-arch=x86-64 --with-tune=generic \
  --with-gnu-as --with-gnu-ld \
  --disable-libstdcxx-pch \
  --disable-libstdcxx-debug 2>&1 | tee --append ../build-${REAL_GCC_VERSION}.log || exit 1
echo "Step B7b: Build and Install boot GCC" >> ${STARTING_FOLDER}/build-${REAL_GCC_VERSION}.log && \
cd ${STARTING_FOLDER}/build-${REAL_GCC_VERSION} && \
make $PARALLEL_MAKE all-gcc 2>&1 | tee --append ../build-${REAL_GCC_VERSION}.log && \
make install-gcc 2>&1 | tee --append ../build-${REAL_GCC_VERSION}.log || exit 1

echo "Step B7c: Build and Install target-libgcc" >> ${STARTING_FOLDER}/build-${REAL_GCC_VERSION}.log && \
cd ${STARTING_FOLDER}/build-${REAL_GCC_VERSION} && \
make $PARALLEL_MAKE all-target-libgcc 2>&1 | tee --append ../build-${REAL_GCC_VERSION}.log && \
make install-target-libgcc 2>&1 | tee --append ../build-${REAL_GCC_VERSION}.log || exit 1

echo "Step B7d: Build and Install target-libada" >> ${STARTING_FOLDER}/build-${REAL_GCC_VERSION}.log && \
cd ${STARTING_FOLDER}/build-${REAL_GCC_VERSION} && \
make $PARALLEL_MAKE all-target-libada 2>&1 | tee --append ../build-${REAL_GCC_VERSION}.log && \
make install-target-libada 2>&1 | tee --append ../build-${REAL_GCC_VERSION}.log || exit 1

echo "Step B7e: Build and Install gnattools" >> ${STARTING_FOLDER}/build-${REAL_GCC_VERSION}.log && \
cd ${STARTING_FOLDER}/build-${REAL_GCC_VERSION} && \
make $PARALLEL_MAKE all-gnattools 2>&1 | tee --append ../build-${REAL_GCC_VERSION}.log && \
make install-gnattools 2>&1 | tee --append ../build-${REAL_GCC_VERSION}.log || exit 1
