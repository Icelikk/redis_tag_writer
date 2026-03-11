cmake_minimum_required(VERSION 3.10)
project(RedisWriter)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(PLOG_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include/plog/include)

find_library(HIREDIS_LIB hiredis /usr/local/lib /usr/lib)
find_path(HIREDIS_INCLUDE hiredis/hiredis.h /usr/local/include /usr/include)

if(NOT HIREDIS_LIB OR NOT HIREDIS_INCLUDE)
    message(FATAL_ERROR "hiredis not found. Please install it first.")
endif()


add_executable(redis_writer redis_writer.cpp)


target_include_directories(redis_writer PRIVATE ${HIREDIS_INCLUDE} ${PLOG_INCLUDE_DIR})

target_link_libraries(redis_writer ${HIREDIS_LIB})