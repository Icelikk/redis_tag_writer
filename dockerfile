FROM registry.astralinux.ru/library/astra/ubi18:latest

RUN apt-get update && apt-get install -y \
    g++ \
    cmake \
    make \
    libhiredis-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
