#!/bin/bash


PERIODS=(100 80 60 40 20)
TAGS_LIST=(100 1000 2000 3000 4000 5000 10000)
DURATION=60
THRESHOLD=10

REDIS_HOST="redis-test"
REDIS_PORT="6379"


opt_results="optimization_results_redis.csv"
all_results="results_redis.csv"

echo "period_ms,max_tags,memory_bytes" > "$opt_results"
echo "period,tags,duration_sec,total_packets,total_records,total_time_ms,time_min,time_max,time_avg,time_stddev,memory_bytes,exceed_count " > "$all_results"

get_redis_memory() {
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INFO memory | grep "used_memory:" | cut -d':' -f2
}

for period in "${PERIODS[@]}"; do
    echo "Тестирование периода $period мс"
    max_success=0
    success_found=false

    for tags in "${TAGS_LIST[@]}"; do
        echo "  Запуск с размером пакета $tags"

        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" EVAL "return redis.call('del', unpack(redis.call('keys', ARGV[1])))" 0 "tag:*" > /dev/null 2>&1
        
        > RedisWriter.log

        log_file="test_p${period}_t${tags}.log"

        timeout $((DURATION + 10)) ./build/redis_writer "$tags" "$period" "$DURATION" > "$log_file" 2>&1
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

        count_tags_val=$(grep -oP 'COUNT_TAGS=\K\d+' "$log_file" | head -1)
        period_ms_val=$(grep -oP 'PERIOD_MS=\K\d+' "$log_file" | head -1)
        work_time_sec=$(grep -oP 'WORK_TIME_SEC=\K\d+' "$log_file" | head -1)
        total_packets=$(grep -oP 'TOTAL_PACKETS=\K\d+' "$log_file" | head -1)
        total_records=$(grep -oP 'TOTAL_RECORDS=\K\d+' "$log_file" | head -1)
        total_time_ms=$(grep -oP 'TOTAL_TIME_MS=\K\d+' "$log_file" | head -1)
        time_min=$(grep -oP 'TIME_MIN=\K\d+' "$log_file" | head -1)
        time_max=$(grep -oP 'TIME_MAX=\K\d+' "$log_file" | head -1)
        time_avg=$(grep -oP 'TIME_AVG=\K[\d.]+' "$log_file" | head -1)
        time_stddev=$(grep -oP 'TIME_STDDEV=\K[\d.]+' "$log_file" | head -1)

        echo "$period,$tags,$DURATION,$total_packets,$total_records,$total_time_ms,$time_min,$time_max,$time_avg,$time_stddev,$memory_bytes,$exceed_count" >> "$all_results"

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