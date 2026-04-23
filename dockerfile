FROM registry.astralinux.ru/library/astra/ubi18-cpp122:latest

RUN apt update && apt install -y \
    libhiredis-dev \
    libpq-dev \
    cmake \
    make \
    git \
    g++ \
    redis-tools \
    postgresql-client \
    coreutils \
    python3 \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /tmp
RUN git clone --branch 7.7.0 https://github.com/jtv/libpqxx.git && \
    cd libpqxx && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_DOC=OFF && \
    make -j$(nproc) && \
    make install && \
    cd ../.. && rm -rf libpqxx

RUN git clone https://github.com/SergiusTheBest/plog.git /tmp/plog --depth=1 && \
    mv /tmp/plog/include/plog /usr/local/include/plog && \
    rm -rf /tmp/plog

WORKDIR /app
COPY . /app

RUN mkdir /tmp/build && \
    cd /tmp/build && \
    cmake /app && \
    make && \
    cp /tmp/build/redis_writer /usr/local/bin/redis_writer && \
    cp /tmp/build/redis_to_pg /usr/local/bin/redis_to_pg && \
    rm -rf /tmp/build

CMD ["/bin/bash"]