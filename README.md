# Redis Benchmark + PostgreSQL Exporter

Проект для нагрузочного тестирования Redis и автоматической выгрузки результатов в PostgreSQL. Измеряет производительность записи пакетов `(id, v, q, t)` и скорость массовой вставки в базу данных.

---


**Требования:** Docker Engine  от 20.10, Docker Compose от 2.0, Git.

**Запуск:** Скопируйте папку с github и запустите docker-compose
```bash

# Клонирование репозитория
git clone https://github.com/Icelikk/redis_tag_writer.git
cd redis_tag_writer

# Запуск в режиме разработки
docker-compose up -d dev

# Подключение к контейнеру
docker exec -it dev-redis bash

# Внутри контейнера: сборка проекта
cd /app
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)

./auto_test_redis.sh                  
./auto_test_redis.sh --without-pg     
```
Есть возможность чистой генерации и записи в Redis, без выгрузки в Postgres по флагу --without-pg 
Результаты сохраняются в папке `test/` в виде CSV-файлов с процентилями P5-P95.
```

## 📁 Структура проекта

```
redis_tag_writer/

├── README.md                     
├── docker-compose.yml            
│
├── src/                         
│   ├── redis_writer.cpp          
│   └── redis_to_pg.cpp           
│
├── docker/                       
│   ├── Dockerfile                
│   └── Dockerfile.dev            
│
├── scripts/                      
│   ├── auto_test_redis.sh        
│   └── unload_redis.sh           
│
├── config/                       
│   └── init.sql                  
│
├── build/                        
│   ├── redis_writer             
│   └── redis_to_pg               
│
└── test/                         
    ├── results_redis.csv        
    ├── optimization_results_redis.csv
    └── *.log                     
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
| `PERIODS`    | Период, с которым программа записывает пакеты данных в Redis(мс)                       | `(100 80 60 40 20)`   |
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

## 🔧 Управление контейнерами

### Основные команды

```bash
# Запуск всех сервисов
docker-compose up -d

# Остановка
docker-compose down

# Пересборка образов
docker-compose build --no-cache

# Просмотр логов
docker-compose logs -f dev
docker-compose logs -f redis
docker-compose logs -f postgres

# Подключение к контейнеру
docker exec -it dev-redis bash

# Очистка volumes (удаляет все данные!)
docker-compose down -v
```

### Ручная выгрузка данных

```bash
# Снаружи контейнера
./scripts/unload_redis.sh <число_пакетов>

# Изнутри контейнера
/app/build/redis_to_pg
```

### Очистка Redis

```bash
docker exec -it dev-redis redis-cli -h redis FLUSHDB
```

### Проверка данных в PostgreSQL

```bash
docker exec -it postgres psql -U postgres -d test -c "SELECT COUNT(*) FROM guts;"
```
## 🛠️ Сборка и разработка

### Development режим

```bash
# Запуск dev-контейнера с примонтированным кодом
docker-compose up -d dev
docker exec -it dev-redis bash

# Внутри контейнера
cd /app

# Полная пересборка
rm -rf build
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)

# Быстрая пересборка после изменений
cmake --build build -j$(nproc)

# Запуск тестов
./scripts/auto_test_redis.sh
```
---

