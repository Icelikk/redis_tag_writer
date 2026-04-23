# Redis Benchmark + PostgreSQL Exporter

Проект для нагрузочного тестирования Redis и автоматической выгрузки результатов в PostgreSQL. Измеряет производительность записи пакетов `(id, v, q, t)` и скорость массовой вставки в базу данных.

---


**Требования:** Docker Engine  от 20.10, Docker Compose от 2.0, Git.

**Запуск:** Скопируйте папку с github и запустите docker-compose
```bash
git clone https://github.com/Icelikk/redis_tag_writer.git
cd redis-benchmark
docker-compose up -d 
```

Подключитесь к контейнеру и запустите тест:

```bash
docker exec -it dev-redis bash

./auto_test_redis.sh                  
./auto_test_redis.sh --without-pg     
```
Есть возможность чистой генерации и записи в Redis, без выгрузки в Postgres по флагу --without-pg 
Результаты сохраняются в папке `/app` внутри контейнера в виде CSV-файлов.

---
## ⚠️ Важно при использовании нескольких проектов
 
Если на этом же сервере запущен другой проект (например, `memc_tag_writer_`) — у него может быть свой контейнер `postgres` на порту `5432`. При попытке поднять этот проект получишь ошибку конфликта портов или имён контейнеров.
 
**Перед запуском остановите старый проект:**
 
```bash
cd /путь/к/другому/проекту
docker-compose down -v
```
 
**Если нужно запустить оба проекта одновременно** — измените порт postgres в `docker-compose.yml` этого проекта:
 
```yaml
postgres:
  ports:
    - "5433:5432"   # внешний порт 5433, внутренний остаётся 5432
```
 
И имя контейнера, чтобы не было конфликта:
 
```yaml
postgres:
  container_name: postgres-redis   # вместо postgres
```
 
> Внутри контейнеров всё общение идёт по внутренним именам сервисов (`postgres`, `redis-test`), так что менять строки подключения в коде не нужно — только `container_name` и проброс портов наружу.
 
---
 

## Структура проекта

```
.
├── dockerfile                # Образ приложения (C++ + зависимости + сборка)
├── docker-compose.yml        # Описание сервисов (redis, postgres, dev)
├── CMakeLists.txt            # Сборка redis_writer и redis_to_pg
├── redis_writer.cpp          # Бенчмарк записи в Redis
├── redis_to_pg.cpp           # Выгрузка из Redis в PostgreSQL
├── auto_test_redis.sh        # Скрипт автоматического тестирования
├── unload_redis.sh           # Скрипт ручной выгрузки
└── init.sql                  # Инициализация схемы PostgreSQL (таблица guts)
```
1. **redis_writer** — записывает пакеты данных в Redis (`LPUSH batch_list`) с заданными периодом и размером пакета.
2. **redis_to_pg** — читает все записи из Redis (`LRANGE batch_list`) и выполняет массовую вставку в PostgreSQL пакетами.
3. **auto_test_redis.sh** — запускает тесты по всем периодам и размерам пакетов, собирает метрики и сохраняет CSV.
4. **unload_redis.sh** — ручная выгрузка данных из Redis в PostgreSQL.

> Бинарники `redis_writer` и `redis_to_pg` собираются при сборке образа и кладутся в `/usr/local/bin/`.

---

## Параметры тестирования

Все параметры задаются в `auto_test_redis.sh`:

| Параметр     | Описание                                          | Значение по умолчанию |
|--------------|---------------------------------------------------|-----------------------|
| `PERIODS`    | период, с которым программа записывает пакеты данных в Redis(мс)                       | `(100 80 60 40 20)`   |
| `TAGS_LIST`  | Размеры пакетов (количество записей за цикл)      | `(100)`               |
| `DURATION`   | Длительность одного теста (сек)                   | `10`                  |
| `THRESHOLD`  | Допустимое количество превышений периода          | `10`                  |

---

## Выходные данные

После запуска в `/app` появятся:

| Файл                             | Содержимое                                                                                           |
|----------------------------------|------------------------------------------------------------------------------------------------------|
| `results_redis.csv`              | Детальная статистика по каждому прогону: период, размер пакета, задержки, превышения, время выгрузки |
| `optimization_results_redis.csv` | Максимальный проходной размер пакета для каждого периода                                             |
| `RedisWriter.log`                | Лог записи (полезен при отладке)                                                                     |

Пример строки в `results_redis.csv`:

```
period,tags,duration_sec,total_packets,total_records,total_time_ms,time_min,time_max,time_avg,time_stddev,insert_min,insert_max,insert_avg,insert_stddev,memory_bytes,exceed_count,unload_time_ms
20,100,10,453,45300,10003,0,2,0.397,0.507,0,2,0.373,0.488,5017320,0,1235
```

---

## Управление контейнерами

**Пересборка образа:**

```bash
docker-compose down
ocker-compose build --no-cache
docker-compose up -d 
```

**Подключение к контейнеру:**

```bash
docker exec -it dev-redis bash
```

**Ручная выгрузка из Redis в PostgreSQL:**

```bash
# Снаружи контейнера:
./unload_redis.sh <число_пакетов>

# Или изнутри контейнера:
/usr/local/bin/redis_to_pg
```

**Просмотр логов:**

```bash
docker-compose logs -f dev
```

**Очистка Redis:**

```bash
docker exec -it dev-redis redis-cli -h redis-test FLUSHDB
```

