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
#include <plog/Appenders/ColorConsoleAppender.h>
#include <plog/Appenders/RollingFileAppender.h>
#include <plog/Formatters/TxtFormatter.h>

int main(int argc, char* argv[]) {
    plog::RollingFileAppender<plog::TxtFormatter> fileAppender("RedisWriter.log");
    plog::ColorConsoleAppender<plog::TxtFormatter> consoleAppender;
    plog::init(plog::debug, &fileAppender).addAppender(&consoleAppender);

    int period_ms = 100;
    int count_tags = 10000;
    int work_time = 60;
    if (argc >= 2) count_tags = std::stoi(argv[1]);
    if (argc >= 3) period_ms = std::stoi(argv[2]);
    if (argc >= 4) work_time = std::stoi(argv[3]);

    PLOGI << "Записей в пакете: " << count_tags;
    PLOGI << "Период цикла = " << period_ms << " мс";
    PLOGI << "Время работы = " << work_time << " с";

    const char* redis_host = "redis";
    int redis_port = 6379;
    redisContext *c = redisConnect(redis_host, redis_port);
    if (c == NULL || c->err) {
        if (c) {
            PLOGE << "Ошибка подключения к Redis: " << c->errstr;
            redisFree(c);
        } else {
            PLOGE << "NULL";
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

    int64_t gen_min = 10000, gen_max = 0;
    double gen_total = 0, gen_sum_sqrt = 0;

    int64_t insert_min = 10000, insert_max = 0;
    double insert_total = 0, insert_sum_sqrt = 0;

    int64_t total_min = 10000, total_max = 0;
    double total_time = 0;
    double total_sum_sqrt = 0;

    while (true) {
        auto now = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(now - program_start).count();
        if (work_time > 0 && elapsed >= work_time) break;

        packet_number++;
        auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count();

        PLOGI << "Пакет номер " << packet_number << " ";

        auto start_gen = std::chrono::steady_clock::now();
        std::vector<uint32_t> ids;      
        std::vector<int16_t> q_vals;
        std::vector<float> v_vals;
        ids.reserve(count_tags);
        q_vals.reserve(count_tags);
        v_vals.reserve(count_tags);

        for (int i = 0; i < count_tags; ++i) {
            uint32_t id = (packet_number * count_tags + i) % 32768;
            int16_t q_val = dis_i(gen);
            float v_val = dis_r(gen);
            ids.push_back(id);
            q_vals.push_back(q_val);
            v_vals.push_back(v_val);
        }
        auto end_gen = std::chrono::steady_clock::now();
        auto gen_duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_gen - start_gen).count();

        PLOGI << "Генерация данных за " << gen_duration << " мс";
        
        if (gen_duration < gen_min) gen_min = gen_duration;
        if (gen_duration > gen_max) gen_max = gen_duration;
        gen_total += gen_duration;
        gen_sum_sqrt += (double)gen_duration * gen_duration;

        auto start_serialize = std::chrono::steady_clock::now();

        std::vector<std::string> records;
        records.reserve(count_tags);
        for (int i = 0; i < count_tags; ++i) {
            std::string rec = std::to_string(ids[i]) + "," +
                              std::to_string(v_vals[i]) + "," +
                              std::to_string(q_vals[i]) + "," +
                              std::to_string(timestamp);
            records.push_back(std::move(rec));
        }

        auto end_serialize = std::chrono::steady_clock::now();
        auto serialize_duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_serialize - start_serialize).count();
        PLOGI << "Сериализация данных за " << serialize_duration << " мс";

        auto start_insert = std::chrono::steady_clock::now();
        std::vector<const char*> argv;
        std::vector<size_t> argvlen;
        argv.push_back("LPUSH");
        argvlen.push_back(5);
        argv.push_back("batch_list");   
        argvlen.push_back(10);          
        
        for (const auto& rec : records) {
            argv.push_back(rec.c_str());
            argvlen.push_back(rec.size());
        }

        redisReply *reply = (redisReply*)redisCommandArgv(c, argv.size(), &argv[0], &argvlen[0]);

        if (!reply) {
            PLOG_WARNING << "Ошибка выполнения LPUSH";
        } else {
            freeReplyObject(reply);
        }

        auto end_insert = std::chrono::steady_clock::now();
        auto insert_duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_insert - start_insert).count();
        PLOGI << "Пакетная вставка за " << insert_duration << " мс";
        
        if (insert_duration < insert_min) insert_min = insert_duration;
        if (insert_duration > insert_max) insert_max = insert_duration;
        insert_total += insert_duration;
        insert_sum_sqrt += (double)insert_duration * insert_duration;

        auto packet_duration = gen_duration + insert_duration + serialize_duration;

        if (packet_duration < total_min) total_min = packet_duration;
        if (packet_duration > total_max) total_max = packet_duration;
        total_time += packet_duration;
        total_sum_sqrt += (double)packet_duration * packet_duration;

        if (packet_duration < period_ms) {
            int sleep_time = period_ms - packet_duration;
            PLOGD << "Ждем " << sleep_time << " мс";
            std::this_thread::sleep_for(std::chrono::milliseconds(sleep_time));
        } else {
            int delay = packet_duration - period_ms;
            PLOG_WARNING << "Превышение времени на " << delay << " мс";
        }
    }

    redisFree(c);
    
    double gen_avg = (packet_number > 0) ? gen_total / packet_number : 0;
    double gen_variance = (packet_number > 0) ? (gen_sum_sqrt / packet_number) - (gen_avg * gen_avg) : 0;
    double gen_stddev = (gen_variance > 0) ? std::sqrt(gen_variance) : 0;

    double insert_avg = (packet_number > 0) ? insert_total / packet_number : 0;
    double insert_variance = (packet_number > 0) ? (insert_sum_sqrt / packet_number) - (insert_avg * insert_avg) : 0;
    double insert_stddev = (insert_variance > 0) ? std::sqrt(insert_variance) : 0;

    double total_avg = (packet_number > 0) ? total_time / packet_number : 0;
    double total_variance = (packet_number > 0) ? (total_sum_sqrt / packet_number) - (total_avg * total_avg) : 0;
    double total_stddev = (total_variance > 0) ? std::sqrt(total_variance) : 0;

    auto program_end = std::chrono::steady_clock::now();
    auto total_duration = std::chrono::duration_cast<std::chrono::milliseconds>(program_end - program_start).count();

    PLOGI << "COUNT_TAGS=" << count_tags;
    PLOGI << "PERIOD_MS=" << period_ms;
    PLOGI << "WORK_TIME_SEC=" << work_time;
    PLOGI << "TOTAL_PACKETS=" << packet_number;
    PLOGI << "TOTAL_RECORDS=" << (packet_number * count_tags);
    PLOGI << "TOTAL_TIME_MS=" << total_duration;
    PLOGI << "TIME_MIN=" << total_min;
    PLOGI << "TIME_MAX=" << total_max;
    PLOGI << "TIME_AVG=" << total_avg;
    PLOGI << "TIME_STDDEV=" << total_stddev;
    PLOGI << "GEN_TIME_MIN=" << gen_min;
    PLOGI << "GEN_TIME_MAX=" << gen_max;
    PLOGI << "GEN_TIME_AVG=" << gen_avg;
    PLOGI << "GEN_TIME_STDDEV=" << gen_stddev;
    PLOGI << "INSERT_TIME_MIN=" << insert_min;
    PLOGI << "INSERT_TIME_MAX=" << insert_max;
    PLOGI << "INSERT_TIME_AVG=" << insert_avg;
    PLOGI << "INSERT_TIME_STDDEV=" << insert_stddev;

    return 0;
}