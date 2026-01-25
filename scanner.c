#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAX_LINE 1024

// Structure to hold function info
typedef struct {
    char return_type[128];
    char name[128];
    char args[256];
} Function;

int main(int argc, char *argv[]) {
    if(argc != 4) {
        printf("Usage: %s <source.c> <output.json> <schema_version>\n", argv[0]);
        return 1;
    }

    const char *source_file = argv[1];
    const char *json_file = argv[2];
    int schema_version = (int)strtol(argv[3], NULL, 10);

    FILE *src = fopen(source_file, "r");
    if(!src) {
        perror("Failed to open source file");
        return 1;
    }

    Function functions[256];
    int func_count = 0;

    char line[MAX_LINE];
    char export_macro[64] = {0};

    // Step 1: detect export macro
    while(fgets(line, sizeof(line), src)) {
        if(strstr(line, "__declspec(dllexport)")) {
            char temp[64];
            if(sscanf(line, "#define %63s", temp) == 1) {
                strcpy(export_macro, temp);
                break;
            }
        }
    }

    if(strlen(export_macro) == 0) {
        fprintf(stderr, "No Windows dllexport macro found in source file\n");
        fclose(src);
        return 1;
    }

    // Reset file pointer to start
    fseek(src, 0, SEEK_SET);

    // Step 2: parse exported functions
    while(fgets(line, sizeof(line), src)) {
        char ret[128], name[128], args[256];
        // Match lines starting with the macro
        if(strncmp(line, export_macro, strlen(export_macro)) == 0) {
            // crude parsing: EXPORT <return_type> <name>(<args>) {
            char *p = line + strlen(export_macro);
            while(*p == ' ' || *p == '\t') p++; // skip spaces

            if(sscanf(p, "%127[^ \t(] %127[^ (] (%255[^)]", ret, name, args) == 3) {
                strcpy(functions[func_count].return_type, ret);
                strcpy(functions[func_count].name, name);
                strcpy(functions[func_count].args, args);
                func_count++;
            }
        }
    }

    fclose(src);

    // Step 3: write JSON
    FILE *out = fopen(json_file, "w");
    if(!out) {
        perror("Failed to open output file");
        return 1;
    }

    // timestamp
    time_t t = time(NULL);
    struct tm lt;
    localtime_s(&lt, &t);
    char timestamp[64];
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%S%z", &lt);

    fprintf(out, "{\n");
    fprintf(out, "   \"schema_version\": %d,\n", schema_version);
    fprintf(out, "   \"source\": \"%s\",\n", source_file);
    fprintf(out, "   \"timestamp\": \"%s\",\n", timestamp);
    fprintf(out, "   \"exported_functions\": [\n");

    for(int i = 0; i < func_count; i++) {
        fprintf(out, "      {\n");
        fprintf(out, "         \"name\": \"%s\",\n", functions[i].name);
        fprintf(out, "         \"return_type\": \"%s\",\n", functions[i].return_type);
        fprintf(out, "         \"args\": \"%s\"\n", functions[i].args);
        fprintf(out, "      }%s\n", (i < func_count-1) ? "," : "");
    }

    fprintf(out, "   ]\n");
    fprintf(out, "}\n");

    fclose(out);

    printf("Found %d exported functions. JSON written to %s\n", func_count, json_file);

    return 0;
}
