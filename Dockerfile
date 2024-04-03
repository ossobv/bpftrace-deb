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
RUN apt-get update -q && \
    apt-get dist-upgrade -y && \
    apt-get install -y \
        ca-certificates curl \
        build-essential devscripts dh-autoreconf dpkg-dev equivs quilt && \
    printf "%s\n" \
        QUILT_PATCHES=debian/patches QUILT_NO_DIFF_INDEX=1 \
        QUILT_NO_DIFF_TIMESTAMPS=1 'QUILT_DIFF_OPTS="--show-c-function"' \
        'QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index"' \
        >~/.quiltrc

# Apt-get prerequisites according to control file.
COPY control /build/debian/control
RUN mk-build-deps --install --remove --tool "apt-get -y" /build/debian/control

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
RUN if ! test -s /build/${upname}_${upversion}.orig.tar.gz; then \
    #url="http://archive.ubuntu.com/ubuntu/pool/universe/b/${upname}/${upname}_${upversion}.orig.tar.gz" && \
    url="https://github.com/${upname}/${upname}/archive/refs/tags/v${upversion}.tar.gz" && \
    echo "Fetching: ${url}" >&2 && \
    curl -fLsS "${url}" -o /build/${upname}_${upversion}.orig.tar.gz; fi
RUN sum=$(md5sum /build/${upname}_${upversion}.orig.tar.gz | awk '{print $1}') && \
    echo "${upversion}: ${sum}" >&2 && \
    case ${upversion} in \
    0.20.3) test "$sum" = 2fad05fd87ccefce5bc58e4f2bc3674a;; \
    0.20.2) test "$sum" = 593db18cf2b541d1f0026d7dc9796269;; \
    0.19.1) test "$sum" = 9a371dffc71824214dc0dd3d57ba3c80;; \
    0.17.1) test "$sum" = 41c7966d306f0e098719374e5d24eae1;; \
    *) false;; \
    esac
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
RUN curl -fLsS https://github.com/libbpf/libbpf/archive/refs/tags/v1.4.0.tar.gz \
      -o ../libbpf-1.4.0.tar.gz && \
    echo '1d1ecd6073cd59f96e780d9858dcde9b  ../libbpf-1.4.0.tar.gz' | md5sum -c && \
    tar zxf ../libbpf-1.4.0.tar.gz && { rmdir libbpf || true; } && ln -s libbpf-1.4.0 libbpf
RUN curl -fLsS https://github.com/iovisor/bcc/archive/refs/tags/v0.30.0.tar.gz \
      -o ../bcc-0.30.0.tar.gz && \
    echo '9d02f4ac5813052cdf449954c945940a  ../bcc-0.30.0.tar.gz' | md5sum -c && \
    tar zxf ../bcc-0.30.0.tar.gz && { rmdir bcc || true; } && ln -s bcc-0.30.0 bcc
# Ignore these extra files in the source dir when checking for changes.
RUN ! test -f debian/source/options && \
    echo 'extend-diff-ignore = "^bcc.*|^libbpf.*"' >debian/source/options

# Build!
RUN DEB_BUILD_OPTIONS=parallel=6 dpkg-buildpackage -us -uc -sa  #|| touch /tmp/fail
#RUN ! test -f /tmp/fail

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
