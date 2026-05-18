FROM registry.astralinux.ru/library/astra/ubi18-cpp122:latest AS builder

RUN apt-get update && apt-get install -y \
    git \
    libhiredis-dev \
    libpq-dev \
    cmake \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*


RUN git clone --depth=1 https://github.com/SergiusTheBest/plog.git /tmp/plog && \
    mv /tmp/plog/include/plog /usr/local/include/plog && rm -rf /tmp/plog

RUN git clone --branch 7.7.0 https://github.com/jtv/libpqxx.git /tmp/libpqxx && \
    cd /tmp/libpqxx && mkdir build && cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_DOC=OFF -DBUILD_TEST=OFF && \
    make -j$(nproc) && make install && cd / && rm -rf /tmp/libpqxx

WORKDIR /app
COPY CMakeLists.txt ./
COPY src/ ./src/

RUN cmake -B build -S . -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build -j$(nproc)

FROM registry.astralinux.ru/library/astra/ubi18-cpp122:latest

RUN apt-get update && apt-get install -y \
    libhiredis0.14 \
    libpq5 \
    postgresql-client \
    redis-tools \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/build/redis_writer /usr/local/bin/redis_writer
COPY --from=builder /app/build/redis_to_pg /usr/local/bin/redis_to_pg

WORKDIR /app
CMD ["/bin/bash"]