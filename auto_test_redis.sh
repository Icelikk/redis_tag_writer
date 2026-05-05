#!/bin/bash
cd /app

WITHOUT_PG=0
if [[ "$1" == "--without-pg" ]]; then
    WITHOUT_PG=1
    shift
fi

PERIODS=(100 80 60 40 20)
TAGS_LIST=(100 1000 2000 5000 10000)
DURATION=30
THRESHOLD=10

REDIS_HOST="redis-test"
REDIS_PORT="6379"

opt_results="optimization_results_redis.csv"
all_results="results_redis.csv"

if [ $WITHOUT_PG -eq 0 ]; then
    echo "period_ms,max_tags,memory_bytes" > "$opt_results"
    echo "period,tags,duration_sec,total_packets,total_records,total_time_ms,time_min,time_max,time_avg,time_stddev,insert_min,insert_max,insert_avg,insert_stddev,memory_bytes,exceed_count,unload_time_ms,p5,p10,p25,p50,p75,p90,p95" > "$all_results"
else
    echo "period_ms,max_tags,memory_bytes" > "$opt_results"
    echo "period,tags,duration_sec,total_packets,total_records,total_time_ms,time_min,time_max,time_avg,time_stddev,insert_min,insert_max,insert_avg,insert_stddev,memory_bytes,exceed_count,p5,p10,p25,p50,p75,p90,p95" > "$all_results"
fi

get_redis_memory() {
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INFO memory | grep "used_memory:" | cut -d':' -f2 | tr -d ' \r\n' || echo "0"
}

flush_redis() {
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" UNLINK batch_list > /dev/null 2>&1
}

flush_postgres() {
    PGPASSWORD=postgres psql -h postgres -U postgres -d test -c "TRUNCATE TABLE guts;" > /dev/null 2>&1
}

calculate_percentiles() {
    local logfile="$1"
    grep -oP 'Пакетная вставка за\s+\K\d+' "$logfile" 2>/dev/null | sort -n | awk '
    {
        arr[NR] = $1
    }
    END {
        if (NR == 0) {
            print "0 0 0 0 0 0 0"
            exit
        }
        p5  = arr[int(NR * 0.05) + 1]
        p10 = arr[int(NR * 0.10) + 1]
        p25 = arr[int(NR * 0.25) + 1]
        p50 = arr[int(NR * 0.50) + 1]
        p75 = arr[int(NR * 0.75) + 1]
        p90 = arr[int(NR * 0.90) + 1]
        p95 = arr[int(NR * 0.95) + 1]
        printf "%d %d %d %d %d %d %d", p5, p10, p25, p50, p75, p90, p95
    }'
}

for period in "${PERIODS[@]}"; do
    echo "Тестирование периода $period мс"
    max_success=0
    success_found=false

    for tags in "${TAGS_LIST[@]}"; do
        echo "  Запуск с размером пакета $tags"

        flush_redis
        flush_postgres

        rm -f RedisWriter.log

        log_file="test_p${period}_t${tags}.log"

        timeout $((DURATION + 10)) /usr/local/bin/redis_writer "$tags" "$period" "$DURATION" > "$log_file" 2>&1
        exit_code=$?

        if [ $exit_code -ne 0 ] && [ $exit_code -ne 124 ]; then
            echo "    Ошибка выполнения (код $exit_code), возможно программа упала"
            break
        fi

        exceed_count=$(grep -c "Превышение времени на" RedisWriter.log 2>/dev/null | tr -d '\n\r')
        exceed_count=${exceed_count:-0}
        echo "    Превышений: $exceed_count"

        memory_bytes=$(get_redis_memory)
        echo "    Память Redis: $memory_bytes байт"
        echo "REDIS_MEMORY=$memory_bytes" >> "$log_file"

        total_packets=$(grep -oP 'TOTAL_PACKETS=\K\d+' RedisWriter.log 2>/dev/null | head -1 | tr -d '\n\r')
        total_records=$(grep -oP 'TOTAL_RECORDS=\K\d+' RedisWriter.log 2>/dev/null | head -1 | tr -d '\n\r')
        total_time_ms=$(grep -oP 'TOTAL_TIME_MS=\K\d+' RedisWriter.log 2>/dev/null | head -1 | tr -d '\n\r')
        time_min=$(grep -oP 'TIME_MIN=\K\d+' RedisWriter.log 2>/dev/null | head -1 | tr -d '\n\r')
        time_max=$(grep -oP 'TIME_MAX=\K\d+' RedisWriter.log 2>/dev/null | head -1 | tr -d '\n\r')
        time_avg=$(grep -oP 'TIME_AVG=\K[\d.]+' RedisWriter.log 2>/dev/null | head -1 | tr -d '\n\r')
        time_stddev=$(grep -oP 'TIME_STDDEV=\K[\d.]+' RedisWriter.log 2>/dev/null | head -1 | tr -d '\n\r')
        insert_min=$(grep -oP 'INSERT_TIME_MIN=\K\d+' RedisWriter.log 2>/dev/null | head -1 | tr -d '\n\r')
        insert_max=$(grep -oP 'INSERT_TIME_MAX=\K\d+' RedisWriter.log 2>/dev/null | head -1 | tr -d '\n\r')
        insert_avg=$(grep -oP 'INSERT_TIME_AVG=\K[\d.]+' RedisWriter.log 2>/dev/null | head -1 | tr -d '\n\r')
        insert_stddev=$(grep -oP 'INSERT_TIME_STDDEV=\K[\d.]+' RedisWriter.log 2>/dev/null | head -1 | tr -d '\n\r')

        read p5 p10 p25 p50 p75 p90 p95 <<< $(calculate_percentiles RedisWriter.log)
        echo "    Процентили: P5=$p5 P10=$p10 P25=$p25 P50=$p50 P75=$p75 P90=$p90 P95=$p95"

        unload_time_ms=""
        if [ $WITHOUT_PG -eq 0 ] && [ -n "$total_packets" ] && [ "$total_packets" -gt 0 ]; then
            unload_output=$(/usr/local/bin/redis_to_pg "$total_packets" 2>&1)
            unload_time_ms=$(echo "$unload_output" | grep -oP '\d+(?= ms)' | head -1 | tr -d '\n\r')
            [ -z "$unload_time_ms" ] && unload_time_ms="error"
            echo "    Выгрузка в PostgreSQL: ${unload_time_ms} мс"
            echo "UNLOAD_TIME_MS=$unload_time_ms" >> "$log_file"
        fi

        if [ $WITHOUT_PG -eq 0 ]; then
            echo "$period,$tags,$DURATION,$total_packets,$total_records,$total_time_ms,$time_min,$time_max,$time_avg,$time_stddev,$insert_min,$insert_max,$insert_avg,$insert_stddev,$memory_bytes,$exceed_count,$unload_time_ms,$p5,$p10,$p25,$p50,$p75,$p90,$p95" >> "$all_results"
        else
            echo "$period,$tags,$DURATION,$total_packets,$total_records,$total_time_ms,$time_min,$time_max,$time_avg,$time_stddev,$insert_min,$insert_max,$insert_avg,$insert_stddev,$memory_bytes,$exceed_count,$p5,$p10,$p25,$p50,$p75,$p90,$p95" >> "$all_results"
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