# Dozzle

[Dozzle](https://dozzle.dev/) is a real time Docker log viewer or partition logs.

```
docker run -d \
--name local-dozzle \
-m 512m \
-p 56101:8080 \
-v /var/run/docker.sock:/var/run/docker.sock \
-v dozzle_data:/data \
amir20/dozzle:latest
```

## First Time

The first time this tool is used, it wil require some set up questions are answered:
- What database should be used to store application settings.
    -- The imbedded database can be used, and not require any outside storage setup.

## Usage

In a browser, open http://localhost:56101
