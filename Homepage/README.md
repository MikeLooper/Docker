# Homepage

[Homepage](https://github.com/gethomepage/homepage) is a highly customizable homepage (or startpage / application dashboard) with Docker and service API integrations.

```
docker run -d \
    --name local-homepage \
    -m 512m \
    -p 56201:56201 \
    --restart=always
```

## Usage

In a browser, open http://localhost:56201
