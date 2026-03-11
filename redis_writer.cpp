#include <iostream>
#include <hiredis/hiredis.h>
#include <chrono>
#include <thread>
#include <random>
#include <cstdlib>
#include <cmath>
#include <iomanip>
#include <vector>
#include <string>

#include <plog/Log.h>
#include <plog/Initializers/RollingFileInitializer.h>

int main(int argc, char* argv[]) {
    
    plog::init(plog::debug, "RedisWriter.log");

    int period_ms = 100;
    int count_tags = 1000;
    int work_time = 60; 

    if (argc >= 2) count_tags = std::stoi(argv[1]);
    if (argc >= 3) period_ms = std::stoi(argv[2]);
    if (argc >= 4) work_time = std::stoi(argv[3]);

    PLOGI << "Записей в пакете: " << count_tags;
    PLOGI << "Период цикла = " << period_ms << " мс";
    PLOGI << "Время работы = " << work_time << " с";

    const char* redis_host = "127.0.0.1";
    int redis_port = 6379;

    redisContext *c = redisConnect(redis_host, redis_port);
    if (c == NULL || c->err) {
        if (c) {
            PLOGE << "Ошибка подключения к Redis: " << c->errstr;
            redisFree(c);
        } else {
            PLOGE << "Не удалось выделить память для контекста Redis";
        }
        return 1;
    }
    PLOGI << "Подключено к Redis";

    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<int16_t> dis_i(1, 20000);
    std::uniform_real_distribution<float> dis_r(1, 1000);

    auto program_start = std::chrono::steady_clock::now();
    int packet_number = 0;
    int64_t time_min = 10000;
    int64_t time_max = 0;
    double total_time = 0;
    double sum_sqrt = 0;

    while (true) {
        auto now = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(now - program_start).count();
        if (work_time > 0 && elapsed >= work_time) break;

        packet_number++;
        auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count();

        PLOGI << "Пакет номер " << packet_number;

        auto start_packet = std::chrono::steady_clock::now();

        redisAppendCommand(c, "MULTI");

        for (int i = 0; i < count_tags; ++i) {
            uint32_t id = (packet_number * count_tags + i) % 32768;
            int16_t q_val = dis_i(gen);
            float v_val = dis_r(gen);

            std::string key = "tag:" + std::to_string(id) + ":" + std::to_string(timestamp);

    
            redisAppendCommand(c, "HMSET %s q %d v %f", key.c_str(), q_val, v_val);
        }
        redisAppendCommand(c, "EXEC");

        for (int i = 0; i < count_tags + 2; ++i) {
            redisReply *reply;
            if (redisGetReply(c, (void**)&reply) == REDIS_OK) {
                freeReplyObject(reply);
            } else {
                PLOG_WARNING << "Ошибка получения ответа от Redis";
            }
        }
        

        auto end_packet = std::chrono::steady_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_packet - start_packet).count();

        PLOGI << "Пакет записан за " << duration << " мс";

        if (duration < time_min) time_min = duration;
        if (duration > time_max) time_max = duration;
        total_time += duration;
        sum_sqrt += duration * duration;

        if (duration < period_ms) {
            int sleep_time = period_ms - duration;
            PLOGD << "Ждем " << sleep_time << " мс";
            std::this_thread::sleep_for(std::chrono::milliseconds(sleep_time));
        } else {
            int delay = duration - period_ms;
            PLOG_WARNING << "Превышение времени на " << delay << " мс";
        }
    }

    redisFree(c);

    double avg_time = (packet_number > 0) ? total_time / packet_number : 0;
    double variance = (packet_number > 0) ? (sum_sqrt / packet_number) - (avg_time * avg_time) : 0;
    double stddev = (variance > 0) ? std::sqrt(variance) : 0;

    auto program_end = std::chrono::steady_clock::now();
    auto total_duration = std::chrono::duration_cast<std::chrono::milliseconds>(program_end - program_start).count();

    std::cout << "COUNT_TAGS=" << count_tags << std::endl;
    std::cout << "PERIOD_MS=" << period_ms << std::endl;
    std::cout << "WORK_TIME_SEC=" << work_time << std::endl;
    std::cout << "TOTAL_PACKETS=" << packet_number << std::endl;
    std::cout << "TOTAL_RECORDS=" << (packet_number * count_tags) << std::endl;
    std::cout << "TOTAL_TIME_MS=" << total_duration << std::endl;
    std::cout << "TIME_MIN=" << time_min << std::endl;
    std::cout << "TIME_MAX=" << time_max << std::endl;
    std::cout << "TIME_AVG=" << avg_time << std::endl;
    std::cout << "TIME_STDDEV=" << stddev << std::endl;

    PLOGI << "COUNT_TAGS=" << count_tags;
    PLOGI << "PERIOD_MS=" << period_ms;
    PLOGI << "WORK_TIME_SEC=" << work_time;
    PLOGI << "TOTAL_PACKETS=" << packet_number;
    PLOGI << "TOTAL_RECORDS=" << (packet_number * count_tags);
    PLOGI << "TOTAL_TIME_MS=" << total_duration;
    PLOGI << "TIME_MIN=" << time_min;
    PLOGI << "TIME_MAX=" << time_max;
    PLOGI << "TIME_AVG=" << avg_time;
    PLOGI << "TIME_STDDEV=" << stddev;

    return 0;
}