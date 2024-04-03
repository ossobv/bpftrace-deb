ARG osdistro=ubuntu
ARG oscodename=jammy

FROM $osdistro:$oscodename
LABEL maintainer="Walter Doekes <wjdoekes+bpftrace@osso.nl>"
LABEL dockerfile-vcs=https://github.com/ossobv/bpftrace-deb

ARG DEBIAN_FRONTEND=noninteractive

# This time no "keeping the build small". We only use this container for
# building/testing and not for running, so we can keep files like apt
# cache. We do this before copying anything and before getting lots of
# ARGs from the user. That keeps this bit cached.
RUN echo 'APT::Install-Recommends "0";' >/etc/apt/apt.conf.d/01norecommends
# We'll be ignoring "debconf: delaying package configuration, since apt-utils
#   is not installed"
RUN . /etc/os-release && \
    apt-get update -q && \
    apt-get dist-upgrade -y && \
    apt-get install -y $force \
        ca-certificates curl \
        build-essential devscripts dh-autoreconf dpkg-dev equivs quilt && \
    printf "%s\n" \
        QUILT_PATCHES=debian/patches QUILT_NO_DIFF_INDEX=1 \
        QUILT_NO_DIFF_TIMESTAMPS=1 'QUILT_DIFF_OPTS="--show-c-function"' \
        'QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index"' \
        >~/.quiltrc

# Apt-get prerequisites according to control file.
COPY control /build/debian/control
RUN . /etc/os-release && \
    mk-build-deps --install --remove --tool "apt-get -y" /build/debian/control
RUN . /etc/os-release && case $VERSION_ID in \
    8) \
        cd /build && \
        curl https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.39/pcre2-10.39.tar.gz \
          -sSfLo pcre2-10.39.tar.gz.tar.gz && \
        test $(md5sum /build/pcre2-10.39.tar.gz.tar.gz | awk '{print $1}' | tee /dev/stderr) = 7389e3524de2cda3d21fde8c224febf1 && \
        tar zxf pcre2-10.39.tar.gz.tar.gz && \
        cd pcre2-10.39 && \
        CFLAGS='-fPIC -O2' ./configure --enable-shared=no --enable-static=yes && \
        make -j6 && \
        make install;; \
    esac

# debian, deb, jessie, bpftrace, 0.17.1, '', 0osso0
ARG osdistro osdistshort oscodename upname upversion debepoch= debversion

COPY changelog /build/debian/changelog.new
RUN . /etc/os-release && \
    sed -i -e "1s/+[^+)]*)/+${osdistshort}${VERSION_ID})/;1s/) stable;/) ${oscodename};/" \
        /build/debian/changelog.new && \
    fullversion="${upversion}-${debversion}+${osdistshort}${VERSION_ID}" && \
    expected="${upname} (${debepoch}${fullversion}) ${oscodename}; urgency=medium" && \
    head -n1 /build/debian/changelog.new && \
    if test "$(head -n1 /build/debian/changelog.new)" != "${expected}"; \
    then echo "${expected}  <-- mismatch" >&2; false; fi

# Trick to allow caching of UPNAME*.tar.gz files. Download them
# once using the curl command below into .cache/* if you want. The COPY
# is made conditional by the "[z]" "wildcard". (We need one existing
# file (README.rst) so the COPY doesn't fail.)
COPY ./README.rst .cache/${upname}_${upversion}.orig.tar.g[z] /build/
# http://archive.ubuntu.com/ubuntu/pool/universe/b/bpftrace/bpftrace_0.20.2.orig.tar.gz
#   593db18cf2b541d1f0026d7dc9796269
# https://github.com/bpftrace/bpftrace/archive/refs/tags/v0.17.1.tar.gz
#   41c7966d306f0e098719374e5d24eae1
RUN if ! test -s /build/${upname}_${upversion}.orig.tar.gz; then \
    #url="http://archive.ubuntu.com/ubuntu/pool/universe/b/${upname}/${upname}_${upversion}.orig.tar.gz" && \
    url="https://github.com/${upname}/${upname}/archive/refs/tags/v${upversion}.tar.gz" && \
    echo "Fetching: ${url}" >&2 && \
    curl -fLsS "${url}" -o /build/${upname}_${upversion}.orig.tar.gz; fi
# 3f464e9187dc812af140dd0f3f1c58f7 = 0.18.6
RUN test $(md5sum /build/${upname}_${upversion}.orig.tar.gz | awk '{print $1}' | \
           tee /dev/stderr) = 41c7966d306f0e098719374e5d24eae1
RUN cd /build && tar zxf "${upname}_${upversion}.orig.tar.gz" && \
    mv debian "${upname}-${upversion}/"
COPY . /build/${upname}-${upversion}/debian/
# Remove data we accidentally copied when doing COPY . -- yes, the Dockerfile
# COPY statement is completely retarded -- and replace the changelog with our
# modified better one.
RUN rm -rf \
      /build/${upname}-${upversion}/debian/README.rst \
      /build/${upname}-${upversion}/debian/.cache && \
    mv -vf /build/${upname}-${upversion}/debian/changelog.new \
           /build/${upname}-${upversion}/debian/changelog
WORKDIR /build/${upname}-${upversion}

# FIXME: Better/earlier download?
# FIXME: md5sum
RUN curl -fLsS https://github.com/libbpf/libbpf/archive/refs/tags/v1.4.0.tar.gz \
      -o ../libbpf-1.4.0.tar.gz && \
    tar zxf ../libbpf-1.4.0.tar.gz && rmdir libbpf && ln -s libbpf-1.4.0 libbpf
RUN curl -fLsS https://github.com/iovisor/bcc/archive/refs/tags/v0.30.0.tar.gz \
      -o ../bcc-0.30.0.tar.gz && \
    tar zxf ../bcc-0.30.0.tar.gz && rmdir bcc && ln -s bcc-0.30.0 bcc
RUN ! test -f debian/source/options && \
    echo 'extend-diff-ignore = "^bcc.*|^libbpf.*"' >debian/source/options
RUN apt-get install -y arping git git-man iperf libbsd-dev \
      libcurl3-gnutls libdbus-1-3 libdebuginfod-common libdebuginfod-dev \
      libdebuginfod1 libedit-dev liberror-perl libmd-dev libnet1 libpcap0.8 \
      netperf python3-distutils

# /usr/bin/c++ -g -O2 -ffile-prefix-map=/build/bpftrace-0.17.1=. -flto=auto -ffat-lto-objects -flto=auto -ffat-lto-objects -fstack-protector-strong -Wformat -Werror=format-security -Wdate-time -D_FORTIFY_SOURCE=2 -Wl,-Bsymbolic-functions -flto=auto -ffat-lto-objects -flto=auto -Wl,-z,relro CMakeFiles/bpftrace.dir/main.cpp.o -o bpftrace  -Wl,-rpath,/usr/lib/llvm-14/lib: libbpftrace.a ../resources/libresources.a libruntime.a ../build-libs/lib64/libbpf.a ../build-libs/lib64/libbcc.a ../build-libs/lib64/libbcc_bpf.a ../build-libs/lib64/libbpf.a ../build-libs/lib64/libbcc.a ../build-libs/lib64/libbcc_bpf.a ../build-libs/lib64/libbcc-loader-static.a /usr/lib/x86_64-linux-gnu/libelf.so /usr/lib/x86_64-linux-gnu/libdw.so -lz aot/libaot.a ast/libast.a ../libparser.a ast/libast_defs.a /usr/lib/llvm-14/lib/libclang-14.so.1 /usr/lib/llvm-14/lib/libLLVM-14.so.1 arch/libarch.a cxxdemangler/libcxxdemangler_llvm.a 
# ./src/driver.cpp:8:14: warning: 'yy_scan_string' violates the C++ One Definition Rule [-Wodr]
# .././obj-x86_64-linux-gnu/lex.yy.cc:2483:17: note: 'yy_scan_string' was previously declared here
# /usr/bin/ld: /tmp/cczqJGkl.ltrans12.ltrans.o: undefined reference to symbol 'lzma_stream_decoder@@XZ_5.0'
# /usr/bin/ld: /lib/x86_64-linux-gnu/liblzma.so.5: error adding symbols: DSO missing from command line
# collect2: error: ld returned 1 exit status
RUN sed -i -e 's/find_package(LibLzma)/#&/' bcc/CMakeLists.txt

# Build!
RUN DEB_BUILD_OPTIONS=parallel=6 dpkg-buildpackage -us -uc -sa || touch /tmp/fail
RUN ! test -f /tmp/fail

# TODO: for bonus points, we could run quick tests here;
# for starters dpkg -i tests?

# Write output files (store build args in ENV first).
ENV oscodename=$oscodename osdistshort=$osdistshort \
    upname=$upname upversion=$upversion debversion=$debversion
RUN . /etc/os-release && fullversion=${upversion}-${debversion}+${osdistshort}${VERSION_ID} && \
    mkdir -p /dist/${upname}_${fullversion} && \
    mv /build/${upname}_${upversion}.orig.tar.gz /dist/${upname}_${fullversion}/ && \
    mv /build/*${fullversion}* /dist/${upname}_${fullversion}/ && \
    cd / && find dist/${upname}_${fullversion} -type f >&2
