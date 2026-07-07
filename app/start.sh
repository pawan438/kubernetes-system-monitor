#!/bin/bash
# Wrapper script: runs health checks in a loop + serves health.log over HTTP

# Start a simple HTTP server in the background, serving files from /app (includes health.log)
python3 -m http.server 8080 --directory /app &

# Run the health check script every 30 seconds, forever
while true; do
    ./main.sh          # run your existing health check logic
    sleep 30           # wait 30 seconds before checking again
done
