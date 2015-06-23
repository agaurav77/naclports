# Copyright (c) 2015 The Native Client Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# falling back to cc for generating build time artifacts
export BUILD_CC=cc
export BUILD_LD=cc
# use -Wno-return-type to suppress return-type errors encountered
# with pnacl, arm's clang-newlib (microperl)
NACLPORTS_CFLAGS_MICRO=$NACLPORTS_CFLAGS
NACLPORTS_CFLAGS_MICRO+=" -Dmain=nacl_main -Wno-return-type "
NACLPORTS_CFLAGS+=" -I${NACL_SDK_ROOT}/include -I${NACLPORTS_INCLUDE} \
  -Wno-return-type"
BUILD_DIR=${SRC_DIR}
# keeping microperl for now
EXECUTABLES="perl microperl"
NACLPORTS_LDFLAGS+=" ${NACL_CLI_MAIN_LIB}"
# we need a working perl on host to build things for target
HOST_BUILD=${WORK_DIR}/build_host
ARCH_DIR=${PUBLISH_DIR}/${NACL_ARCH}
LIBS=" ${NACL_CLI_MAIN_LIB}"
# PNaCl and newlib dont have dynamic loading, so
# using Perl's internal stub file dl_none.xs
# specifically for systems which do not support it
# Also, FILE pointer is structured a bit differently
# Relevant stdio parameters found via sel_ldr on Linux
if [ "${NACL_LIBC}" = "newlib" -o "${NACL_ARCH}" = "pnacl" ] ; then
  NACLPORTS_CFLAGS+=" -I${NACLPORTS_INCLUDE}/glibc-compat "
  LIBS+=" -lm -ltar -lglibc-compat "
  DYNAMIC_EXT="undef"
  NACL_GLIBC_DEF="undef"
  PERL_STDIO_BASE="(((fp)->_bf)._base)"
  PERL_STDIO_BUFSIZ="(((fp)->_bf)._size)"
  PERL_STDIO_CNT=""
  PERL_STDIO_PTR="((fp)->_p)"
  PERL_DLSRC="dl_none.xs"
  NACLPORTS_CCDLFLAGS=""
else
  LIBS+=" -ldl -lm -ltar"
  DYNAMIC_EXT="Cwd Fcntl Math/BigInt/FastCalc Opcode PerlIO/encoding \
               PerlIO/mmap PerlIO/scalar PerlIO/via POSIX"
  NACL_GLIBC_DEF="define"
  PERL_STDIO_BASE="((fp)->_IO_read_base)"
  PERL_STDIO_BUFSIZ="((fp)->_IO_read_end - (fp)->_IO_read_base)"
  PERL_STDIO_CNT="((fp)->_IO_read_end - (fp)->_IO_read_ptr)"
  PERL_STDIO_PTR="((fp)->_IO_read_ptr)"
  PERL_DLSRC="dl_dlopen.xs"
  NACLPORTS_CCDLFLAGS="-Wl,-E"
fi

# BuildHostMiniperl builds miniperl for host, which is needed for
# building Perl for the target
BuildHostMiniperl() {
  if [ ! -x ${HOST_BUILD}/miniperl ]; then
    MakeDir ${HOST_BUILD}
    ChangeDir ${SRC_DIR}
    LogExecute ${SRC_DIR}/Configure -des -Dprefix=${HOST_BUILD} \
      -DNACL_BUILD=host
    LogExecute make -j${OS_JOBS} NACL_BUILD=host miniperl
    LogExecute cp miniperl ${HOST_BUILD}
  fi
}

# This is required to change the parameters in config.sh as according
# to their values on host, since just using them in config.sh (after
# export) doesn't work
# TODO(agaurav77): Maybe use a better way.
SedWork() {
  sed -i "s%\${NACLAR}%${NACLAR}%g" $1
  sed -i "s%\${NACLRANLIB}%${NACLRANLIB}%g" $1
  sed -i "s%\${NACL_ARCH}%${NACL_ARCH}%g" $1
  sed -i "s%\${NACLCC}%${NACLCC}%g" $1
  sed -i "s%\${NACLPORTS_CFLAGS}%${NACLPORTS_CFLAGS}%g" $1
  sed -i "s%\${NACLPORTS_CCDLFLAGS}%${NACLPORTS_CCDLFLAGS}%g" $1
  sed -i "s%\${NACLCXX}%${NACLCXX}%g" $1
  sed -i "s%\${BUILD_DIR}%${BUILD_DIR}%g" $1
  sed -i "s%\${HOST_BUILD}%${HOST_BUILD}%g" $1
  sed -i "s%\${NACLPORTS_INCLUDE}%${NACLPORTS_INCLUDE}%g" $1
  sed -i "s%\${NACLPORTS_LDFLAGS}%${NACLPORTS_LDFLAGS}%g" $1
  sed -i "s%\${NACLPORTS_LIBDIR}%${NACLPORTS_LIBDIR}%g" $1
  sed -i "s%\${DYNAMIC_EXT}%${DYNAMIC_EXT}%g" $1
  sed -i "s%\$NACL_GLIBC_DEF%${NACL_GLIBC_DEF}%g" $1
  sed -i "s%\${PERL_STDIO_BASE}%${PERL_STDIO_BASE}%g" $1
  sed -i "s%\${PERL_STDIO_BUFSIZ}%${PERL_STDIO_BUFSIZ}%g" $1
  sed -i "s%\${PERL_STDIO_CNT}%${PERL_STDIO_CNT}%g" $1
  sed -i "s%\${PERL_STDIO_PTR}%${PERL_STDIO_PTR}%g" $1
  sed -i "s%\${PERL_DLSRC}%${PERL_DLSRC}%g" $1
}

# copy perl_pepper.c to source directory for core perl
PatchStep() {
  DefaultPatchStep
  LogExecute cp ${START_DIR}/perl_pepper.c ${SRC_DIR}
}

ConfigureStep() {
  BuildHostMiniperl
  LogExecute cp ${START_DIR}/config ${BUILD_DIR}/config.sh
  LogExecute SedWork ${BUILD_DIR}/config.sh
  ChangeDir ${BUILD_DIR}
  # all these SH files pick up values from config.sh
  ./config_h.SH
  ./metaconfig.SH
  chmod a+x pod/Makefile.SH
  ./pod/Makefile.SH
  ./makedepend.SH
  ./cflags.SH
  ./Makefile.SH
  ./myconfig.SH
  ./runtests.SH
  ./Policy_sh.SH
  ./x2p/Makefile.SH
}

BuildStep() {
  # clean up previous executables
  LogExecute make -j${OS_JOBS} -f Makefile.micro clean
  # microperl build from Makefile.micro
  LogExecute make -j${OS_JOBS} -f Makefile.micro CC="${NACLCC}" \
    CCFLAGS=" -c -DHAS_DUP2 -DPERL_MICRO ${NACLPORTS_CFLAGS_MICRO}" \
    LDFLAGS="${NACLPORTS_LDFLAGS}"
  # now make perl
  echo "MAKING PERL"
  #LogExecute make -j${OS_JOBS} clean
  LogExecute ${BUILD_CC} -c -DPERL_CORE -fwrapv -fno-strict-aliasing -pipe \
    -O2 -Wall generate_uudmap.c
  LogExecute ${BUILD_LD} -o generate_uudmap generate_uudmap.o -lm
  LogExecute make -j${OS_JOBS} libs="${LIBS}" all
  # test_prep prepares the perl for tests, might use this later
  LogExecute make -j${OS_JOBS} libs="${LIBS}" test_prep
}

InstallStep() {
  # microperl doesn't require make install
  return
}

PublishStep() {
  MakeDir ${ARCH_DIR}
  TAR_DIR=${ARCH_DIR}/perltar
  MakeDir ${TAR_DIR}
  ChangeDir ${TAR_DIR}
  LogExecute cp -rf ${SRC_DIR}/lib ${TAR_DIR}
  LogExecute tar cf ${ARCH_DIR}/perl.tar .
  ChangeDir ${SRC_DIR}
  LogExecute rm -rf ${TAR_DIR}
  PublishByArchForDevEnv
}
