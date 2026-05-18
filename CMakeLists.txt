cmake_minimum_required(VERSION 3.16)
project(RedisWriter LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG")

find_library(HIREDIS_LIB hiredis)
find_path(HIREDIS_INCLUDE_DIR hiredis/hiredis.h)

find_package(PostgreSQL REQUIRED)
find_library(PQXX_LIB NAMES pqxx)
find_path(PQXX_INCLUDE_DIR NAMES pqxx/pqxx)

if(NOT PQXX_LIB OR NOT PQXX_INCLUDE_DIR)
    message(FATAL_ERROR "libpqxx not found")
endif()

add_executable(redis_writer src/redis_writer.cpp)
add_executable(redis_to_pg src/redis_to_pg.cpp)

target_include_directories(redis_writer PRIVATE 
    ${HIREDIS_INCLUDE_DIR} 
    /usr/local/include
)

target_include_directories(redis_to_pg PRIVATE 
    ${HIREDIS_INCLUDE_DIR} 
    ${PostgreSQL_INCLUDE_DIRS} 
    ${PQXX_INCLUDE_DIR} 
    /usr/local/include
)

target_link_libraries(redis_writer PRIVATE ${HIREDIS_LIB})

target_link_libraries(redis_to_pg PRIVATE 
    ${PQXX_LIB} 
    ${PostgreSQL_LIBRARIES} 
    ${HIREDIS_LIB} 
    pq
)