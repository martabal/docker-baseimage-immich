# syntax=docker/dockerfile:1

FROM ghcr.io/martabal/baseimage-ubuntu:noble

# set version label
ARG BUILD_DATE
ARG VERSION

ARG LATEST_UBUNTU_VERSION="questing"
ARG INTEL_DEPENDENCIES_VERSION="latest"
ARG INTEL_DEPENDENCIES_LEGACY_VERSION="24.35.30872.22"

# hadolint ignore=DL3048
LABEL build_version="Build-date:- ${BUILD_DATE}"
LABEL maintainer="martabal"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# run build
# hadolint ignore=DL3003,DL3008,SC2046
RUN \
  mkdir -p \
    /app/immich/server/geodata \
    /tmp/immich-dependencies && \
  if [ $(arch) = "x86_64" ]; then \
    UBUNTU_REPO="http://archive.ubuntu.com/ubuntu/"; \
  else \
    UBUNTU_REPO="http://ports.ubuntu.com/ubuntu-ports/"; \
  fi && \
  printf "deb ${UBUNTU_REPO} ${LATEST_UBUNTU_VERSION} main restricted universe multiverse\ndeb-src ${UBUNTU_REPO} ${LATEST_UBUNTU_VERSION} main restricted universe multiverse" >> /etc/apt/sources.list && \
  printf "Package: *\nPin: release n=${LATEST_UBUNTU_VERSION}\nPin-Priority: 450" > /etc/apt/preferences.d/preferences && \
  echo "**** install build packages ****" && \
  apt-get update && \
  apt-get install --no-install-recommends -y \
    autoconf \
    bc \
    build-essential \
    cmake \
    git \
    libaom-dev \
    libde265-dev \
    libexif-dev \
    libexpat1-dev \
    libglib2.0-dev \
    libgsf-1-dev \
    libheif-dev \
    libjpeg-dev \
    libltdl-dev \
    libbrotli-dev \
    librsvg2-dev \
    libspng-dev \
    libtool \
    libwebp-dev \
    meson \
    pkg-config \
    unzip && \
  apt-get install --no-install-recommends -y -t ${LATEST_UBUNTU_VERSION} \
    libdav1d-dev \
    libhwy-dev \
    libwebp-dev && \
  echo "**** install runtime packages ****" && \
  apt-get install --no-install-recommends -y \
    libaom3 \
    libde265-0 \
    libexif12 \
    libexpat1 \
    libgcc-s1 \
    libglib2.0-0 \
    libgomp1 \
    libgsf-1-114 \
    libio-compress-brotli-perl \
    liblcms2-2 \
    liblqr-1-0 \
    libltdl7 \
    libmimalloc2.0 \
    libopenexr-3-1-30 \
    libopenjp2-7 \
    libpng16-16 \
    librsvg2-2 \
    libspng0 \
    mesa-utils \
    mesa-va-drivers \
    mesa-vulkan-drivers \
    zlib1g && \
  apt-get install --no-install-recommends -y -t ${LATEST_UBUNTU_VERSION} \
    libdav1d7 \
    libhwy1t64 \
    libwebp7 \
    libwebpdemux2 \
    libwebpmux3 && \
  if [ $(arch) = "x86_64" ]; then \
    echo "**** install legacy intel dependencies ****" && \
    apt-get install --no-install-recommends -y \
      intel-media-va-driver-non-free \
      ocl-icd-libopencl1 && \
    if [ -n "$INTEL_DEPENDENCIES_LEGACY_VERSION" ]; then \
      mkdir -p \
        /tmp/intel/legacy && \
      INTEL_LEGACY_DEPENDENCIES=$(curl -sX GET "https://api.github.com/repos/intel/compute-runtime/releases/tags/${INTEL_DEPENDENCIES_LEGACY_VERSION}" | jq -r '.body' | grep wget | grep -v .sum | grep -v .ddeb | sed 's|wget ||g') && \
      mkdir -p /tmp/intel-legacy && \
      for i in $INTEL_LEGACY_DEPENDENCIES; do \
        curl -fS --retry 3 --retry-connrefused -o \
          /tmp/intel-legacy/$(basename "${i%$'\r'}") -L \
          "${i%$'\r'}" || exit 1; \
      done && \
      dpkg -i /tmp/intel-legacy/*.deb; \
    fi; \
    echo "**** install intel dependencies ****" && \
    if [ -z "${INTEL_DEPENDENCIES_VERSION}" ] || [ "${INTEL_DEPENDENCIES_VERSION}" = "latest" ]; then \
      LATEST_VERSION=$(curl -sfX GET "https://api.github.com/repos/intel/compute-runtime/releases/latest" | jq -r '.tag_name'); \
      INTEL_DEPENDENCIES_VERSION="tags/${LATEST_VERSION}"; \
    else \
      INTEL_DEPENDENCIES_VERSION="tags/${INTEL_DEPENDENCIES_VERSION}"; \
    fi && \
    INTEL_DEPENDENCIES=$(curl -sfX GET "https://api.github.com/repos/intel/compute-runtime/releases/${INTEL_DEPENDENCIES_VERSION}" | jq -r '.assets[].browser_download_url' | grep -v .sum | grep -v .ddeb) && \
    IGC_VERSION=$(curl -sfX GET "https://api.github.com/repos/intel/intel-graphics-compiler/releases/latest" | jq -r '.tag_name') && \
    INTEL_DEPENDENCIES="${COMP_RT_URLS} $(curl -sfX GET https://api.github.com/repos/intel/intel-graphics-compiler/releases/tags/${IGC_VERSION} | jq -r '.assets[].browser_download_url' | grep -v devel)" && \
    mkdir -p /tmp/intel && \
    for i in $INTEL_DEPENDENCIES; do \
      curl -fS --retry 3 --retry-connrefused -o \
        /tmp/intel/$(basename "${i%$'\r'}") -L \
        "${i%$'\r'}" || exit 1; \
    done && \
    dpkg -i /tmp/intel/*.deb; \
  fi && \
  echo "**** download base-images ****" && \
  if [ -z "${VERSION}" ]; then \
    VERSION=$(curl -sL https://api.github.com/repos/immich-app/base-images/tags | \
        jq -r '.[0].name'); \
  fi && \
  curl -o \
    /tmp/immich-dependencies.tar.gz -L \
    "https://github.com/immich-app/base-images/archive/refs/tags/${VERSION}.tar.gz" && \
  tar xf \
    /tmp/immich-dependencies.tar.gz -C \
    /tmp/immich-dependencies --strip-components=1 && \
  echo "**** build immich dependencies ****" && \
  cd /tmp/immich-dependencies/server/sources && \
  FFMPEG_VERSION=$(jq -cr '.version' /tmp/immich-dependencies/server/packages/ffmpeg.json) && \
  TARGETARCH=${TARGETARCH:=$(dpkg --print-architecture)} && \
  curl -o \
    /tmp/ffmpeg.deb -L \
    "https://github.com/jellyfin/jellyfin-ffmpeg/releases/download/v${FFMPEG_VERSION}/jellyfin-ffmpeg7_${FFMPEG_VERSION}-noble_${TARGETARCH}.deb" && \
  apt-get install --no-install-recommends -y -f \
    /tmp/ffmpeg.deb && \
  ldconfig /usr/lib/jellyfin-ffmpeg/lib && \
  ln -s /usr/lib/jellyfin-ffmpeg/ffmpeg /usr/bin && \
  ln -s /usr/lib/jellyfin-ffmpeg/ffprobe /usr/bin && \
  ./libjxl.sh \
    --JPEGLI_LIBJPEG_LIBRARY_SOVERSION 8 \
    --JPEGLI_LIBJPEG_LIBRARY_VERSION 8.2.2 && \
  ./libheif.sh && \
  ./libraw.sh && \
  ./imagemagick.sh && \
  ./libvips.sh && \
  jq -s '.' /tmp/immich-dependencies/server/packages/*.json > /tmp/packages.json && \
  jq -s '.' /tmp/immich-dependencies/server/sources/*.json > /tmp/sources.json && \
  jq -n \
    --slurpfile sources /tmp/sources.json \
    --slurpfile packages /tmp/packages.json \
    '{sources: $sources[0], packages: $packages[0]}' \
    > /app/immich/server/build-lock.json && \
  echo "**** download geocoding data ****" && \
  curl -o \
    /tmp/cities500.zip -L \
    "https://download.geonames.org/export/dump/cities500.zip" && \
  curl -o \
    /app/immich/server/geodata/admin1CodesASCII.txt -L \
    "https://download.geonames.org/export/dump/admin1CodesASCII.txt" && \
  curl -o \
    /app/immich/server/geodata/admin2Codes.txt -L \
    "https://download.geonames.org/export/dump/admin2Codes.txt" && \
  curl -o \
    /app/immich/server/geodata/ne_10m_admin_0_countries.geojson -L \
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson" && \
  unzip \
    /tmp/cities500.zip -d \
    /app/immich/server/geodata && \
  date --iso-8601=seconds | tr -d "\n" > /app/immich/server/geodata/geodata-date.txt && \
  echo "**** cleanup ****" && \
  apt-get remove -y --purge \
    autoconf \
    bc \
    build-essential \
    cmake \
    git \
    libdav1d-dev \
    libde265-dev \
    libexif-dev \
    libexpat1-dev \
    libglib2.0-dev \
    libgsf-1-dev \
    libjpeg-dev \
    libltdl-dev \
    libbrotli-dev \
    librsvg2-dev \
    libspng-dev \
    libtool \
    meson \
    pkg-config \
    unzip && \
  apt-get autoremove -y --purge && \
  apt-get clean && \
  head -n -2 /etc/apt/sources.list > /tmp/sources.list && \
  mv \
    /tmp/sources.list \
    /etc/apt/sources.list && \
  rm -rf \
    /etc/apt/preferences.d/preferences \
    /tmp/* \
    /var/lib/apt/lists/* \
    /var/log/* \
    /var/tmp/*
