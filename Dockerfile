###############################################################################
# Soliplex frontend client
###############################################################################
# Usage:
#
# 1. Build the image (from the frontend directory):
#
#    $ docker build . -t soliplex-frontend:latest
#
# 2. Run the Soliplex front-end client:
#
#    $ docker run --rm -p 9000:9000 soliplex-frontend:latest
#
# To cache-bust the web assets (see scripts/post-build-cache-bust.sh), pass a
# release tag or commit SHA when building:
#
#    $ docker build . -t soliplex-frontend:latest \
#        --build-arg RELEASE_HASH=$(git rev-parse --short HEAD)
#
# To build only the web tree, as an image for other images to 'COPY --from='
# (what .github/workflows/image.yaml publishes on each release):
#
#    $ docker build . --target web -t soliplex-frontend-web:latest \
#        --build-arg RELEASE_HASH=$(git rev-parse --short HEAD)
#
###############################################################################

###############################################################################
# Build stage
###############################################################################
# The web build is platform-independent static files, so build it on the
# builder's own platform: a multi-platform build then runs Flutter once, not
# under emulation for each target.
FROM --platform=$BUILDPLATFORM ubuntu:focal AS builder

#------------------------------------------------------------------------------
# Install system utilities / prereqs.
#------------------------------------------------------------------------------
RUN apt-get update && \
    apt-get install \
        --no-install-recommends -y \
        ca-certificates \
        git \
        curl \
        wget \
        unzip \
        xz-utils \
        jq && \
    rm -rf /var/lib/apt/lists/*

#------------------------------------------------------------------------------
# Download and install flutter. The version comes from .fvmrc, which is also
# what CI reads; copy it alone so a version bump invalidates this layer and
# nothing earlier.
#------------------------------------------------------------------------------
COPY .fvmrc /tmp/.fvmrc

RUN export FLUTTER=flutter_linux_$(jq -r '.flutter' /tmp/.fvmrc)-stable.tar.xz && \
    mkdir -p /opt &&  \
    cd /opt && \
    curl -fL -o $FLUTTER https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/$FLUTTER && \
    tar xf $FLUTTER && \
    rm $FLUTTER

#------------------------------------------------------------------------------
# Copy local source into the build context.
#------------------------------------------------------------------------------
COPY . /app

#------------------------------------------------------------------------------
# Build flutter web app. '--no-web-resources-cdn' bundles CanvasKit rather
# than loading it from Google's CDN. Text fonts still come from Google Fonts
# (the engine's 'fontFallbackBaseUrl'): the build bundles only MaterialIcons.
#------------------------------------------------------------------------------
ARG FLUTTER_BUILD_ARGS="--release --no-tree-shake-icons --no-web-resources-cdn"

RUN cd /app && \
    export FLUTTER=/opt/flutter/bin/flutter && \
    git config --global --add safe.directory /opt/flutter && \
    $FLUTTER --disable-analytics && \
    $FLUTTER clean && \
    $FLUTTER pub get && \
    $FLUTTER build web $FLUTTER_BUILD_ARGS

#------------------------------------------------------------------------------
# Optionally cache-bust the web assets. The hash has to come in as a build arg:
# .dockerignore excludes .git, so the build cannot derive it. Declared after
# the build so a new hash reruns only this step.
#------------------------------------------------------------------------------
ARG RELEASE_HASH=""

RUN if [ -n "$RELEASE_HASH" ]; then \
      /app/scripts/post-build-cache-bust.sh /app/build/web; \
    fi

###############################################################################
# Web stage — only the built web tree, at /build/web
###############################################################################
# Published as ghcr.io/soliplex/frontend-web, for images that serve the client
# with their own web server:
#
#    COPY --from=ghcr.io/soliplex/frontend-web:<version> /build/web <dest>
#
FROM scratch AS web

COPY --from=builder /app/build/web /build/web

###############################################################################
# Dev stage — flutter web dev server with hot reload
###############################################################################
FROM builder AS dev

WORKDIR /app

ENV FLUTTER=/opt/flutter/bin/flutter
ENV PATH="/opt/flutter/bin:${PATH}"

EXPOSE 9000

# Source is bind-mounted at /app; pub get runs at startup to pick up changes.
# --web-port matches the exposed port; --web-hostname 0.0.0.0 makes it
# reachable from outside the container.
CMD git config --global --add safe.directory /opt/flutter && \
    git config --global --add safe.directory /app && \
    flutter pub get && \
    flutter run -d web-server --web-port=9000 --web-hostname=0.0.0.0

###############################################################################
# Production stage with nginx
###############################################################################
FROM nginx:alpine

#------------------------------------------------------------------------------
# Copy built flutter web app to nginx html directory
#------------------------------------------------------------------------------
COPY --from=builder /app/build/web /app/build/web

#------------------------------------------------------------------------------
# Copy nginx configuration
#------------------------------------------------------------------------------
COPY nginx/nginx.conf /etc/nginx/nginx.conf

EXPOSE 9000

CMD ["nginx", "-g", "daemon off;"]