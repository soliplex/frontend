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
###############################################################################

###############################################################################
# Build stage
###############################################################################
FROM ubuntu:focal AS builder

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
# Build flutter web app
#------------------------------------------------------------------------------
RUN cd /app && \
    export FLUTTER=/opt/flutter/bin/flutter && \
    git config --global --add safe.directory /opt/flutter && \
    $FLUTTER --disable-analytics && \
    $FLUTTER clean && \
    $FLUTTER pub get && \
    $FLUTTER build web --release --no-tree-shake-icons

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