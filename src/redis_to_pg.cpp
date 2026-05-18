#include <hiredis/hiredis.h>
#include <libpq-fe.h>
#include <iostream>
#include <chrono>
#include <string>
#include <vector>

int main() {
    redisContext *redis = redisConnect("redis", 6379);
    if (!redis || redis->err) {
        std::cerr << "Ошибка подключения к Redis: " 
                  << (redis ? redis->errstr : "null") << std::endl;
        if (redis) redisFree(redis);
        return 1;
    }

    PGconn *pg = PQconnectdb("host=postgres port=5432 dbname=test user=postgres password=postgres");
    if (PQstatus(pg) != CONNECTION_OK) {
        std::cerr << "Ошибка подключения к PostgreSQL: " << PQerrorMessage(pg) << std::endl;
        PQfinish(pg);
        redisFree(redis);
        return 1;
    }

    PQexec(pg, "SET synchronous_commit = OFF");
    PQexec(pg, "SET temp_buffers = '256MB'");
    PQexec(pg, "SET maintenance_work_mem = '256MB'");

    auto start = std::chrono::steady_clock::now();

    redisReply *reply = (redisReply*)redisCommand(redis, "LRANGE batch_list 0 -1");
    if (!reply || reply->type != REDIS_REPLY_ARRAY) {
        std::cerr << "Ошибка команды LRANGE" << std::endl;
        if (reply) freeReplyObject(reply);
        redisFree(redis);
        PQfinish(pg);
        return 1;
    }

    const size_t BATCH_SIZE = 5000;         
    std::vector<std::string> buffer;
    buffer.reserve(BATCH_SIZE);

    auto flush = [&]() {
        if (buffer.empty()) return;

        const char *copy_cmd = "COPY guts (id, v, q, t) FROM STDIN WITH (FORMAT csv)";
        PGresult *res = PQexec(pg, copy_cmd);
        if (PQresultStatus(res) != PGRES_COPY_IN) {
            std::cerr << "Ошибка COPY: " << PQerrorMessage(pg) << std::endl;
            PQclear(res);
            return;
        }
        PQclear(res);

        for (const auto& row : buffer) {
            std::string line = row + '\n';
            if (PQputCopyData(pg, line.c_str(), line.size()) <= 0) {
                std::cerr << "Ошибка PQputCopyData" << std::endl;
                PQputCopyEnd(pg, "error");
                return;
            }
        }

        PQputCopyEnd(pg, NULL);
        buffer.clear();
    };

    size_t total = 0;
    for (size_t i = 0; i < reply->elements; ++i) {
        if (reply->element[i]->type == REDIS_REPLY_STRING) {
            buffer.emplace_back(reply->element[i]->str, reply->element[i]->len);
            ++total;
            if (buffer.size() >= BATCH_SIZE) flush();
        }
    }
    flush();  

    freeReplyObject(reply);
    redisFree(redis);
    PQfinish(pg);

    auto end = std::chrono::steady_clock::now();
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

    std::cout << "Обработано записей: " << total << std::endl;
    std::cout << "Общее время: " << ms << " мс" << std::endl;
    return 0;
}