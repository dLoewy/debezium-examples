#!/usr/local/bin/bash

# Parse inputs
TABLE_SHAPE=$1
SERIALIZATION=$2
echo "Table shape: $TABLE_SHAPE"
echo "Serialization: $SERIALIZATION"

# Prepare SQL for creating and inserting to table, based on "tall" vs "wide" case
STR_VAL="'a123456789b123456789'"
if [[ $TABLE_SHAPE == 'tall' ]]; then
  CREATE_TABLE_SQL="create table disktest (id int not null auto_increment primary key, str0 varchar(255));"
  INSERT_ROW_SQL="insert into disktest (str0) values ($STR_VAL);"
  MAX_SIZE=5000 # Add data to MySQL table until this many KB are reported by INFORMATION_SCHEMA
  NUM_INSERTS=10000 # Number of INSERTS to generate in loaddb.sql file
elif [[ $TABLE_SHAPE == 'wide' ]]; then
  CREATE_TABLE_SQL="create table disktest (id int not null auto_increment primary key, str0 varchar(255), str1 varchar(255), str2 varchar(255), str3 varchar(255), str4 varchar(255), str5 varchar(255), str6 varchar(255), str7 varchar(255), str8 varchar(255), str9 varchar(255));"
  INSERT_ROW_SQL="insert into disktest (str0, str1, str2, str3, str4, str5, str6, str7, str8, str9) values ($STR_VAL, $STR_VAL, $STR_VAL, $STR_VAL, $STR_VAL, $STR_VAL, $STR_VAL, $STR_VAL, $STR_VAL, $STR_VAL);"
  MAX_SIZE=10000 # Add data to MySQL table until this many KB are reported by INFORMATION_SCHEMA
  NUM_INSERTS=2000 # Number of INSERTS to generate in loaddb.sql file
else
  echo "Unrecognized TABLE_SHAPE: $TABLE_SHAPE"
  exit
fi
echo "CREATE_TABLE_SQL: $CREATE_TABLE_SQL"
echo "INSERT_ROW_SQL: $INSERT_ROW_SQL"

# Choose Docker Compose file based on desired serialization format
if [[ $SERIALIZATION == 'json' ]]; then
  DC_FILE=docker-compose-mysql.yaml
elif [[ $SERIALIZATION == 'avro' ]]; then
  DC_FILE=docker-compose-mysql-avro-worker.yaml
else
  echo "Unrecognized SERIALIZATION: $SERIALIZATION"
  exit
fi

# Start the topology as defined in https://debezium.io/docs/tutorial/
export DEBEZIUM_VERSION=1.6
docker-compose -f $DC_FILE up > /dev/null &

# Wait for Kafka Connect to accept requests
while true; do
  if curl -sf http://localhost:8083/connectors/; then
    break
  fi
  echo 'Not up yet, waiting 1 sec'
  sleep 1
done

# Start MySQL connector
curl -i -X POST -H "Accept:application/json" -H  "Content-Type:application/json" http://localhost:8083/connectors/ -d @register-mysql.json

# Modify records in the database via MySQL client
MYSQL_ROOT_PASSWORD=$(docker-compose -f $DC_FILE exec mysql bash -c 'echo -n $MYSQL_ROOT_PASSWORD')

# Initialize SQL file to insert
: > loaddb.sql
for i in $(seq 1 $NUM_INSERTS); do
  echo "$INSERT_ROW_SQL" >> loaddb.sql
done

RESULT_FILE="result_${TABLE_SHAPE}_${SERIALIZATION}.csv"
echo 'ROW_COUNT,TABLE_SIZE,DU_SIZE,KAFKA_SIZE' > $RESULT_FILE
docker-compose -f $DC_FILE exec mysql mysql -u root -p$MYSQL_ROOT_PASSWORD inventory -e "$CREATE_TABLE_SQL"
TABLE_SIZE=0
while (( $TABLE_SIZE < $MAX_SIZE )); do
  docker-compose -f $DC_FILE exec -T mysql mysql -u root -p$MYSQL_ROOT_PASSWORD inventory < loaddb.sql
  ROW_COUNT=$(docker-compose -f $DC_FILE exec -T mysql mysql -u root -p$MYSQL_ROOT_PASSWORD inventory -N -e "select count(*) from disktest;")
  TABLE_SIZE=$(docker-compose -f $DC_FILE exec -T mysql mysql -u root -p$MYSQL_ROOT_PASSWORD inventory -N -e "SELECT (data_length+index_length) DIV 1024 tablesize FROM information_schema.tables WHERE table_schema='inventory' and table_name='disktest';")
  DU_SIZE=$(docker-compose -f $DC_FILE exec mysql du -s /var/lib/mysql/inventory/disktest.ibd | cut -f1)
  KAFKA_SIZE=$(docker-compose -f $DC_FILE exec kafka du -s /kafka/data/1/dbserver1.inventory.disktest-0 | cut -f1)
  OUT="$ROW_COUNT,$TABLE_SIZE,$DU_SIZE,$KAFKA_SIZE"
  echo "OUT: $OUT"
  echo $OUT >> $RESULT_FILE
done

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