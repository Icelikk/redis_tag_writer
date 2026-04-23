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

RUN rm -rf /app/build && \
    mkdir /app/build && \
    cd /app/build && \
    cmake .. && \
    make

CMD ["/bin/bash"]