import json
import sys

labels = sys.argv[1:]

with open("config.json") as file:
    config = json.load(file)

for label in labels:
    if label in config:
        print(config[label])
        sys.exit(0)
    else:
        sys.exit(1)