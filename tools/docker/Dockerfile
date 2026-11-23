# Lua 5.1 toolchain matching the WoW client's Lua dialect: busted (tests) + luacheck (lint).
FROM alpine:3.20
RUN apk add --no-cache lua5.1 lua5.1-dev luarocks5.1 build-base git \
 && luarocks-5.1 install busted 2.2.0-1 \
 && luarocks-5.1 install luacheck 1.2.0-1 \
 && apk del build-base
WORKDIR /src
