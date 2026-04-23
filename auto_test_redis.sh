#!/bin/bash
cd /app

WITHOUT_PG=0
if [[ "$1" == "--without-pg" ]]; then
    WITHOUT_PG=1
    shift
fi

PERIODS=(100 80 60 40 20)
TAGS_LIST=(100)
DURATION=10
THRESHOLD=10

REDIS_HOST="redis-test"
REDIS_PORT="6379"

opt_results="optimization_results_redis.csv"
all_results="results_redis.csv"


if [ $WITHOUT_PG -eq 0 ]; then
    echo "period_ms,max_tags,memory_bytes" > "$opt_results"
    echo "period,tags,duration_sec,total_packets,total_records,total_time_ms,time_min,time_max,time_avg,time_stddev,insert_min,insert_max,insert_avg,insert_stddev,memory_bytes,exceed_count,unload_time_ms" > "$all_results"
else
    echo "period_ms,max_tags,memory_bytes" > "$opt_results"
    echo "period,tags,duration_sec,total_packets,total_records,total_time_ms,time_min,time_max,time_avg,time_stddev,insert_min,insert_max,insert_avg,insert_stddev,memory_bytes,exceed_count" > "$all_results"
fi

get_redis_memory() {
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INFO memory | grep "used_memory:" | cut -d':' -f2 | tr -d '\n\r'
}

flush_redis() {
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" EVAL "return redis.call('del', unpack(redis.call('keys', ARGV[1])))" 0 "tag:*" > /dev/null 2>&1
}

flush_postgres() {
    PGPASSWORD=postgres psql -h postgres -U postgres -d test -c "TRUNCATE TABLE guts;" > /dev/null 2>&1
}

for period in "${PERIODS[@]}"; do
    echo "Тестирование периода $period мс"
    max_success=0
    success_found=false

    for tags in "${TAGS_LIST[@]}"; do
        echo "  Запуск с размером пакета $tags"

        flush_redis
        flush_postgres

        > RedisWriter.log

        log_file="test_p${period}_t${tags}.log"

        timeout $((DURATION + 10)) /app/build/redis_writer "$tags" "$period" "$DURATION" > "$log_file" 2>&1
        exit_code=$?

        if [ $exit_code -ne 0 ] && [ $exit_code -ne 124 ]; then
            echo "    Ошибка выполнения (код $exit_code), возможно программа упала"
            break
        fi

        exceed_count=$(grep -c "Превышение времени на" RedisWriter.log)
        echo "    Превышений: $exceed_count"

        memory_bytes=$(get_redis_memory)
        echo "    Память Redis: $memory_bytes байт"
        echo "REDIS_MEMORY=$memory_bytes" >> "$log_file"

        total_packets=$(grep -oP 'TOTAL_PACKETS=\K\d+' RedisWriter.log | head -1)
        total_records=$(grep -oP 'TOTAL_RECORDS=\K\d+' RedisWriter.log | head -1)
        total_time_ms=$(grep -oP 'TOTAL_TIME_MS=\K\d+' RedisWriter.log | head -1)
        time_min=$(grep -oP 'TIME_MIN=\K\d+' RedisWriter.log | head -1)
        time_max=$(grep -oP 'TIME_MAX=\K\d+' RedisWriter.log | head -1)
        time_avg=$(grep -oP 'TIME_AVG=\K[\d.]+' RedisWriter.log | head -1)
        time_stddev=$(grep -oP 'TIME_STDDEV=\K[\d.]+' RedisWriter.log | head -1)
        insert_min=$(grep -oP 'INSERT_TIME_MIN=\K\d+' RedisWriter.log | head -1)
        insert_max=$(grep -oP 'INSERT_TIME_MAX=\K\d+' RedisWriter.log | head -1)
        insert_avg=$(grep -oP 'INSERT_TIME_AVG=\K[\d.]+' RedisWriter.log | head -1)
        insert_stddev=$(grep -oP 'INSERT_TIME_STDDEV=\K[\d.]+' RedisWriter.log | head -1)

        unload_time_ms=""
        if [ $WITHOUT_PG -eq 0 ] && [ -n "$total_packets" ] && [ "$total_packets" -gt 0 ]; then
            unload_output=$(/app/build/redis_to_pg "$total_packets" 2>&1)
            unload_time_ms=$(echo "$unload_output" | grep -oP '\d+(?= ms)' | head -1)
            if [ -z "$unload_time_ms" ]; then
                unload_time_ms="error"
            fi
            echo "    Выгрузка в PostgreSQL: ${unload_time_ms} мс"
            echo "UNLOAD_TIME_MS=$unload_time_ms" >> "$log_file"
        fi

       
        if [ $WITHOUT_PG -eq 0 ]; then
            echo "$period,$tags,$DURATION,$total_packets,$total_records,$total_time_ms,$time_min,$time_max,$time_avg,$time_stddev,$insert_min,$insert_max,$insert_avg,$insert_stddev,$memory_bytes,$exceed_count,$unload_time_ms" >> "$all_results"
        else
            echo "$period,$tags,$DURATION,$total_packets,$total_records,$total_time_ms,$time_min,$time_max,$time_avg,$time_stddev,$insert_min,$insert_max,$insert_avg,$insert_stddev,$memory_bytes,$exceed_count" >> "$all_results"
        fi

        if [ "$exceed_count" -gt "$THRESHOLD" ]; then
            echo "    Порог превышен, остановка для периода $period"
            break
        else
            max_success=$tags
            success_found=true
        fi
    done

    if [ "$success_found" = true ]; then
        echo "Для периода $period максимальный проходной размер: $max_success"
        echo "$period,$max_success,$memory_bytes" >> "$opt_results"
    else
        echo "Для периода $period нет успешных тестов"
        echo "$period,0,$memory_bytes" >> "$opt_results"
    fi
done

echo "Готово. Результаты в $all_results и $opt_results"