#!/bin/bash

if [ -n "$1" ]; then
    PACKETS=$1
else
    if [ ! -f RedisWriter.log ]; then
        echo "RedisWriter.log not found. Please specify number of packets."
        exit 1
    fi
    PACKETS=$(grep -oP 'TOTAL_PACKETS=\K\d+' RedisWriter.log | tail -1)
    if [ -z "$PACKETS" ]; then
        echo "No TOTAL_PACKETS found in RedisWriter.log"
        exit 1
    fi
fi

docker exec dev-redis ./build/redis_to_pg "$PACKETS"