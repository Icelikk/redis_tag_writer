#include <hiredis/hiredis.h>
#include <pqxx/pqxx>
#include <iostream>
#include <chrono>
#include <string>
#include <vector>

int main() {
    redisContext *c = redisConnect("redis", 6379);
    if (c == NULL || c->err) {
        std::cerr << "Redis connection error: " << (c ? c->errstr : "NULL") << std::endl;
        return 1;
    }

    pqxx::connection conn("host=postgres port=5432 dbname=test user=postgres password=postgres");
    if (!conn.is_open()) {
        std::cerr << "PG connection failed" << std::endl;
        redisFree(c);
        return 1;
    }

    auto start = std::chrono::steady_clock::now();

    redisReply *reply = (redisReply*)redisCommand(c, "LRANGE batch_list 0 -1");
    if (!reply || reply->type != REDIS_REPLY_ARRAY) {
        std::cerr << "LRANGE failed" << std::endl;
        if (reply) freeReplyObject(reply);
        redisFree(c);
        return 1;
    }

    const size_t BATCH_SIZE = 1000;
    std::vector<std::string> buffer;
    buffer.reserve(BATCH_SIZE);

    auto flush_buffer = [&]() {
        if (buffer.empty()) return;
        pqxx::work txn(conn);
        std::string sql = "INSERT INTO guts (id, v, q, t) VALUES ";
        for (size_t i = 0; i < buffer.size(); ++i) {
            if (i > 0) sql += ",";
            sql += "(" + buffer[i] + ")";
        }
        txn.exec(sql);
        txn.commit();
        buffer.clear();
    };

    size_t total_records = reply->elements;
    for (size_t i = 0; i < total_records; ++i) {
        if (reply->element[i]->type == REDIS_REPLY_STRING) {
            buffer.push_back(std::string(reply->element[i]->str, reply->element[i]->len));
            if (buffer.size() >= BATCH_SIZE) {
                flush_buffer();
            }
        }
    }
    flush_buffer();

    redisReply *delReply = (redisReply*)redisCommand(c, "UNLINK batch_list");
    if (delReply) freeReplyObject(delReply);

    freeReplyObject(reply);
    redisFree(c);

    auto end = std::chrono::steady_clock::now();
    auto duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

    std::cout << "Processed " << total_records << " records in " << duration_ms << " ms" << std::endl;
    return 0;
}