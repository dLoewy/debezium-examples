#!/usr/local/bin/bash

DC_FILE=docker-compose-mysql-nodb.yaml

# Start the topology as defined in https://debezium.io/docs/tutorial/
export DEBEZIUM_VERSION=1.8
# docker-compose -f $DC_FILE up > /dev/null &
docker-compose -f $DC_FILE up &

# Wait for Kafka Connect to accept requests
while true; do
  if curl -sf http://localhost:8083/connectors/; then
    break
  fi
  echo 'Not up yet, waiting 1 sec'
  sleep 1
done

# Start MySQL connector
curl -s -X POST -H "Accept:application/json" -H  "Content-Type:application/json" http://localhost:8083/connectors/ -d @register-mysql-ci.json

docker-compose -f $DC_FILE exec kafka /kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server kafka:9092 \
    --from-beginning \
    --property print.key=true \
    --topic dbserver1.ds2.test

# Shut down the cluster
docker-compose -f $DC_FILE down

###### SCRATCH ######
# docker-compose -f $DC_FILE exec mysql bash
# # Consume messages from a Debezium topic
# docker-compose -f $DC_FILE exec kafka /kafka/bin/kafka-console-consumer.sh \
#     --bootstrap-server kafka:9092 \
#     --from-beginning \
#     --property print.key=true \
#     --topic dbserver1.inventory.customers