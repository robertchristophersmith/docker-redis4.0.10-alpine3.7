FROM alpine:3.7

LABEL maintainer="Robert C Smith <robert@robertcsmith.me>"

ENV REDIS_VERSION 4.0.11
ENV REDIS_DOWNLOAD_URL http://download.redis.io/releases/redis-4.0.11.tar.gz
ENV REDIS_DOWNLOAD_SHA256 fc53e73ae7586bcdacb4b63875d1ff04f68c5474c1ddeda78f00e5ae2eed1bbb

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN set -ex; \
    addgroup --system redis 2>/dev/null; \
    adduser --system --no-create-home --ingroup redis redis 2>/dev/null; \
# grab su-exec for easy step-down from root
    apk add --no-cache 'su-exec>=0.2' tzdata; \
	\
	apk add --no-cache --virtual .build-deps \
		coreutils \
		gcc \
		jemalloc-dev \
		linux-headers \
		make \
		musl-dev \
        tar \
        xz \
		wget \
	; \
	\
	wget -O /redis.tar.gz "$REDIS_DOWNLOAD_URL"; \
	echo "$REDIS_DOWNLOAD_SHA256 *redis.tar.gz" | sha256sum -c -; \
	mkdir -p /usr/src/redis; \
	tar -xzf /redis.tar.gz -C /usr/src/redis --strip-components=1; \
	rm -rf /redis.tar.gz; \
# disable Redis protected mode [1] as it is unnecessary in context of Docker
# (ports are not automatically exposed when running inside Docker, but rather explicitly by specifying -p / -P)
# [1]: https://github.com/antirez/redis/commit/edd4d555df57dc84265fdfb4ef59a4678832f6da
	grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 1$' /usr/src/redis/src/server.h; \
	sed -ri 's!^(#define CONFIG_DEFAULT_PROTECTED_MODE) 1$!\1 0!' /usr/src/redis/src/server.h; \
	grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 0$' /usr/src/redis/src/server.h; \
# for future reference, we modify this directly in the source instead of just supplying a default configuration flag because apparently "if you specify any argument to redis-server, [it assumes] you are going to specify everything"
# see also https://github.com/docker-library/redis/issues/4#issuecomment-50780840
# (more exactly, this makes sure the default behavior of "save on SIGTERM" stays functional by default)
	make -C /usr/src/redis -j "$(nproc)"; \
	make -C /usr/src/redis install; \
	rm -rf /usr/src/redis; \
	\
	runDeps="$(scanelf --needed --nobanner --format '%n#p' --recursive /usr/local | tr ',' '\n'  | sort -u | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' )"; \
	apk add --no-cache --virtual .redis-rundeps $runDeps; \
	\
	apk del .build-deps; \
	mkdir /data; \
    chown redis:redis /data; \
    chmod 0770 /data;

VOLUME /data

WORKDIR /data

COPY docker-entrypoint.sh /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# EXPOSE 6379

CMD ["redis-server"]
