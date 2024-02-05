#!/bin/bash

start_containers() {
  echo "Starting user defined bridge network..." 
  docker network create custom_nw 2>/dev/null || true

  echo "Starting DB container..."
  docker build -t my_db_image -f Dockerfile_mysql .
  DBID=$(docker run -d -p 3306:3306 -e MYSQL_ROOT_PASSWORD=pw --net custom_nw --name my_db my_db_image)

  echo "Waiting for MySQL to be ready..."
  until docker exec $DBID mysqladmin ping -h"localhost" --silent; do
    echo -n "."
    sleep 1
  done
  echo "MySQL is up and running!"

  DBHOST=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DBID)
  export DBHOST
  export DBPORT=3306

  docker build -t app_image .

  echo "Starting webserver containers..."
  (docker run -p 8081:8080 -e DBHOST=$DBHOST -e DBPORT=$DBPORT -e APP_COLOR="blue" --net custom_nw -d --name app_blue app_image && echo "App1 started") &
  (docker run -p 8082:8080 -e DBHOST=$DBHOST -e DBPORT=$DBPORT -e APP_COLOR="pink" --net custom_nw -d --name app_pink app_image && echo "App2 started") &
  (docker run -p 8083:8080 -e DBHOST=$DBHOST -e DBPORT=$DBPORT -e APP_COLOR="lime" --net custom_nw -d --name app_lime app_image && echo "App3 started") &

  wait  # Wait for all background processes to finish
  echo "All containers started!"

  echo "Starting reverse-proxy from port 8080 to containers..."
  docker build -t nginx-reverse-proxy -f Dockerfile_nginx .
  docker run -d -p 8080:80 -e DBHOST=$DBHOST -e DBPORT=$DBPORT --net custom_nw --name reverse-proxy nginx-reverse-proxy
}

stop_and_cleanup() {
  echo "Stopping and removing docker containers..."
  docker rm $(docker stop $(docker ps -a -q))

  echo "Deleting all docker images..."
  docker rmi -f $(docker images -q)

  echo "Deleting docker user network ..."
  docker network rm custom_nw
}

echo "Select an action:"
echo "1. Start containers"
echo "2. Delete containers, images and user network"
read -p "Enter your choice (1/2): " choice

case "$choice" in
  "1")
    start_containers
    ;;
  "2")
    stop_and_cleanup
    ;;
  *)
    echo "Invalid choice. Please select 1 or 2."
    exit 1
    ;;
esac

exit 0
