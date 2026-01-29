#include <stdio.h>
#include <stdbool.h>

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT
#endif

EXPORT int fast_add(int a, int b) {
    return a + b;
}

EXPORT void greet(void) {
    printf("Hello, world from GCC compiler!\n");
}

EXPORT bool add() {
    return true;
}