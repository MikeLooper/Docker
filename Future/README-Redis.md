# Docker - Setup - Redis

Redis provides solutions for caching, vector search, and NoSQL databases that seamlessly fit into any tech stack—making it simple for digital customers to build, scale, and deploy the fast apps our world runs on.

Refs: 
- Home: https://redis.io/open-source/
- Docs: https://redis.io/docs/latest/get-started/
- Dicker image: https://hub.docker.com/_/redis

Details that support the Build and Run Steps can be found in the sections below the Build and Run Steps section.

The setup processing steps are described below, but can also be found as a [batch file](.\Docker-Redis-builder.bat).

## Build and Run Steps

1. Pull the Redis Docker image

Visit Docker Hub and select a version of Redis image you would like to deploy. Then run the following command in your terminal to pull the specific Redis Docker image.

```
docker pull redis:alpine3.23
```

Remember to replace the version with the docker image tag of your choice.

2. Start Redis

For a minimal installation of Infisical, you must configure ENCRYPTION_KEY, AUTH_SECRET, DB_CONNECTION_URI, SITE_URL, and REDIS_URL. [View all available configurations](https://infisical.com/docs/self-hosting/configuration/envars).

## Security

For the ease of accessing Redis from other containers via Docker networking, the "Protected mode" is turned off by default. This means that if you expose the port outside of your host (e.g., via -p on docker run), it will be open without a password to anyone. It is highly recommended to set a password (by supplying a config file) if you plan on exposing your Redis instance to the internet. For further information, see the following links about Redis security:

- [Redis documentation on security](https://redis.io/docs/latest/operate/oss_and_stack/management/security/)
- [Protected mode](https://redis.io/docs/latest/operate/oss_and_stack/management/security/#protected-mode)
- [A few things about Redis security by antirez](http://antirez.com/news/96)

## Process User and Privileges

By default, the Redis Docker image drops privileges by switching to the redis user and removing unnecessary capabilities. This step is skipped if Docker is run with the --user option or if you set the SKIP_DROP_PRIVS=1 (since 8.0.2) environment variable.

Note: Using SKIP_DROP_PRIVS is not recommended, as it reduces the container's security.

## How to use this image

### Start a redis instance

```
$ docker run --name some-redis -d redis
```

### Start with persistent storage

```
$ docker run --name some-redis -d redis redis-server --save 60 1 --loglevel warning
```

There are several different persistence strategies to choose from. This one will save a snapshot of the DB every 60 seconds if at least 1 write operation was performed (it will also lead to more logs, so the loglevel option may be desirable). If persistence is enabled, data is stored in the VOLUME /data, which can be used with --volumes-from some-volume-container or -v /docker/host/dir:/data (see [docs.docker volumes](https://docs.docker.com/engine/tutorials/dockervolumes/?_gl=1*r5fe6v*_gcl_au*MTMxNDYzNDU0OC4xNzgzNDYyNjA0LjUwNjM2MjMwOS4xNzgzNDY0MzkzLjE3ODM0NjQ0Mzc.*_ga*MzkwNDc1MDU0LjE3ODM0NjI2MDQ.*_ga_XJWPQMJYHQ*czE3ODU3MTgxMzckbzEwJGcxJHQxNzg1NzE4MzM3JGoyOSRsMCRoMA..)).

For more about Redis persistence, see [the official Redis documentation](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/).

#### File and Directory Permissions

Redis will attempt to correct the ownership and permissions of the data and configuration (since 8.0.2) directories and files if they are not set correctly. This adjustment is only performed in basic, default scenarios to avoid interfering with custom or user-specific configurations.

You can skip this step by setting the SKIP_FIX_PERMS=1(since 8.0.2) environment variable.

#### Manually Setting File and Directory Permissions

If you prefer to handle file permissions yourself, you can use a docker run command to set the correct ownership on mounted volumes. For example:

```
$ docker run --rm -v /your/host/path:/data redis chown -R redis:redis /data
```

### Connecting via redis-cli

```
$ docker run -it --network some-network --rm redis redis-cli -h some-redis
```

### Additionally, if you want to use your own redis.conf ...

You can create your own Dockerfile that adds a redis.conf from the context into /data/, like so.

```
FROM redis
COPY redis.conf /usr/local/etc/redis/redis.conf
CMD [ "redis-server", "/usr/local/etc/redis/redis.conf" ]
```

Alternatively, you can specify something along the same lines with docker run options.

```
$ docker run -v /myredis/conf:/usr/local/etc/redis --name myredis redis redis-server /usr/local/etc/redis/redis.conf
```

Where /myredis/conf/ is a local directory containing your redis.conf file. Using this method means that there is no need for you to have a Dockerfile for your redis container.

The mapped directory should be writable, as depending on the configuration and mode of operation, Redis may need to create additional configuration files or rewrite existing ones.

## Image Variants

The redis images come in many flavors, each designed for a specific use case.

```
redis:<version>
```

This is the defacto image. If you are unsure about what your needs are, you probably want to use this one. It is designed to be used both as a throw away container (mount your source code and start the container to start your app), as well as the base to build other images off of.

Some of these tags may have names like bookworm or trixie in them. These are the suite code names for releases of [Debian](https://wiki.debian.org/DebianReleases) and indicate which release the image is based on. If your image needs to install any additional packages beyond what comes with the image, you'll likely want to specify one of these explicitly to minimize breakage when there are new releases of Debian.

redis:<version>-alpine
This image is based on the popular [Alpine Linux project](https://alpinelinux.org/), available in the [alpine official image](https://hub.docker.com/_/alpine). Alpine Linux is much smaller than most distribution base images (~5MB), and thus leads to much slimmer images in general.

This variant is useful when final image size being as small as possible is your primary concern. The main caveat to note is that it does use [musl](https://musl.libc.org/) libc instead of [glibc and friends](https://www.etalabs.net/compare_libcs.html), so software will often run into issues depending on the depth of their libc requirements/assumptions. See [this Hacker News comment thread](https://news.ycombinator.com/item?id=10782897) for more discussion of the issues that might arise and some pro/con comparisons of using Alpine-based images.

To minimize image size, it's uncommon for additional related tools (such as git or bash) to be included in Alpine-based images. Using this image as a base, add the things you need in your own Dockerfile (see the alpine [image description](https://hub.docker.com/_/alpine/) for examples of how to install packages if you are unfamiliar).

## License

Starting with Redis 8.0, Redis follows a tri-licensing model with the choice of the [Redis Source Available License v2 - RSALv2](https://redis.io/legal/rsalv2-agreement/), [Server Side Public License v1 - SSPLv1](https://redis.io/legal/server-side-public-license-sspl/), or the [GNU Affero General Public License v3 - AGPLv3](https://opensource.org/license/agpl-v3). Prior versions of Redis (<=7.2.4) are licensed under [3-Clause BSD](https://opensource.org/license/bsd-3-clause)⁠, and Redis 7.4.x-7.8.x are licensed under the dual [RSALv2](https://redis.io/legal/rsalv2-agreement/) or [SSPLv1](https://redis.io/legal/server-side-public-license-sspl/) license.

Please also view the [Redis License Overview](https://redis.io/legal/licenses/) and the [Redis Trademark Policy](https://redis.io/legal/trademark-policy/).

As with all Docker images, these likely also contain other software which may be under other licenses (such as Bash, etc from the base distribution, along with any direct or indirect dependencies of the primary software being contained).

Some additional license information which was able to be auto-detected might be found in the [repo-info repository's redis/ directory](https://github.com/docker-library/repo-info/tree/master/repos/redis).

As for any pre-built image usage, it is the image user's responsibility to ensure that any use of this image complies with any relevant licenses for all software contained within.
