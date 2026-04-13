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
        xz-utils && \
    rm -rf /var/lib/apt/lists/*

#------------------------------------------------------------------------------
# Download and install flutter.
#------------------------------------------------------------------------------
RUN export FLUTTER=flutter_linux_3.38.4-stable.tar.xz && \
    mkdir -p /opt &&  \
    cd /opt && \
    curl -L -o $FLUTTER https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/$FLUTTER && \
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
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 9000

CMD ["nginx", "-g", "daemon off;"]