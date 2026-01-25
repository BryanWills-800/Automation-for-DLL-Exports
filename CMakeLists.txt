cmake_minimum_required(VERSION 3.10)

project(myffi LANGUAGES C)

add_library(myffi SHARED
        mylib.c
)
