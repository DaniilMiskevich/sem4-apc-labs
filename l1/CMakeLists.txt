cmake_minimum_required(VERSION 3.5)

project(l VERSION 1.0.0 LANGUAGES C)


set(SRCS_PATH "src/*.c")
set(INCLUDE_DIR "include/")

file(GLOB_RECURSE SRCS ${SRCS_PATH})


set(MAIN "main")

add_executable(${MAIN} ${SRCS})
target_include_directories(${MAIN} PRIVATE ${INCLUDE_DIR})

target_compile_options(${MAIN} PUBLIC
    -Og -g -Wall -Wextra -Wformat -fsanitize=address)
target_link_options(${MAIN} PUBLIC
    -Og -g -Wall -Wextra -Wformat -fsanitize=address)

