# Uptime Kuma

[Uptime Kuma](https://uptime.kuma.pet/) Simple up or down checks and status pages.

```
docker run -d \
-p 3001:3001 \
-m 512m \
--name local_uptimekuma \
--restart=always \
-v uptime-kuma:/app/data \
-v /var/run/docker.sock:/var/run/docker.sock \
louislam/uptime-kuma:latest
```

## First Time

The first time this tool is used, it wil require some set up questions are answered:
- a user name
- a user password

## Usage

In a browser, open http://localhost:3001

## Configure the Docker Host

1. Open your Uptime Kuma dashboard (usually http://localhost:3001).
2. Click on Settings in the top right corner.
3. Select Docker Hosts from the sidebar menu.
4. Click Setup Docker Host and fill out the fields:
- Friendly Name: Local Docker Host
- Connection Type: Socket
- Docker Daemon Socket: /var/run/docker.sock
5. Click Test to ensure the connection succeeds, then click Save.

## Create a Container Monitor

1. Go back to the main dashboard and click Add New Monitor.
2. Set the Monitor Type to Docker Container.
3. Fill out the configuration parameters:
- Friendly Name: Name of your service (e.g., My Database).
- Docker Host: Select Local Docker Host (configured in Step 2).
- Container Name / ID: Enter the precise container name or container ID from docker ps.
4. Configure your preferred Heartbeat Interval and Retries.
5. Scroll to the bottom and click Save.

Your container is now actively monitored, and its status will turn green if it is running correctly. 
For further advanced settings or to monitor remote servers via TCP, check out the official [Uptime Kuma GitHub Wiki](https://github.com/louislam/uptime-kuma/wiki/How-to-Monitor-Docker-Containers).

