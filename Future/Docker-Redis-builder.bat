REM Docker - Setup - Redis

REM 1. Remove a previously existing partition, if any is present:
docker rm -f local_redis

REM 2. Download the Redis image:
docker pull redis:alpine3.23

REM 3. Create and start the new container:
docker run -p 6379:6379 --name local_redis --network pilot-net -m 512m -d redis:alpine3.23
