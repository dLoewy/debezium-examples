#!/usr/local/bin/bash

DC_FILE=docker-compose-mysql.yaml

# Start the topology as defined in https://debezium.io/docs/tutorial/
export DEBEZIUM_VERSION=1.6
docker-compose -f $DC_FILE up > /dev/null &

# Modify records in the database via MySQL client
MYSQL_ROOT_PASSWORD=debezium

# Wait for MySQL to accept requests
while true; do
  docker-compose -f $DC_FILE exec -T mysql mysql -u root -p$MYSQL_ROOT_PASSWORD inventory << EOF       
select 1;
EOF
  if [[ $? == 0 ]]; then
    break
  fi
  echo 'MySQL not up yet, waiting 1 sec'
  sleep 1
done

docker-compose -f $DC_FILE exec -T mysql mysql -u root -p$MYSQL_ROOT_PASSWORD << EOF
GRANT RELOAD, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'debezium_r' IDENTIFIED BY 'dbz';
GRANT SELECT ON inventory.* TO 'debezium_r' IDENTIFIED BY 'dbz';
EOF

# Wait for Kafka Connect to accept requests
while true; do
  if curl -sf http://localhost:8083/connectors/; then
    break
  fi
  echo 'Kafka Connect not up yet, waiting 1 sec'
  sleep 1
done

# Start MySQL connector
curl -i -X POST -H "Accept:application/json" -H  "Content-Type:application/json" http://localhost:8083/connectors/ -d @register-mysql-restricted.json

docker-compose -f $DC_FILE exec kafka /kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server kafka:9092 \
    --from-beginning \
    --property print.key=true \
    --topic dbserver1.inventory.customers

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