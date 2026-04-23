cmake_minimum_required(VERSION 3.10)
project(RedisWriter)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG")
set(CMAKE_BUILD_TYPE Release)

set(PLOG_INCLUDE_DIR /usr/local/include)

find_library(HIREDIS_LIB hiredis)
find_path(HIREDIS_INCLUDE hiredis/hiredis.h)

find_package(PostgreSQL REQUIRED)

find_library(PQXX_LIB NAMES pqxx)
find_path(PQXX_INCLUDE NAMES pqxx/pqxx)

if(NOT PQXX_LIB OR NOT PQXX_INCLUDE)
    message(FATAL_ERROR "libpqxx not found")
endif()

add_executable(redis_writer redis_writer.cpp)
target_include_directories(redis_writer PRIVATE ${HIREDIS_INCLUDE} ${PLOG_INCLUDE_DIR})
target_link_libraries(redis_writer ${HIREDIS_LIB})

add_executable(redis_to_pg redis_to_pg.cpp)
target_include_directories(redis_to_pg PRIVATE ${HIREDIS_INCLUDE} ${PostgreSQL_INCLUDE_DIRS} ${PQXX_INCLUDE})
target_link_libraries(redis_to_pg ${PQXX_LIB} ${PostgreSQL_LIBRARIES} ${HIREDIS_LIB} pq)