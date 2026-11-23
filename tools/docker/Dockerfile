# Lua 5.1 toolchain matching the WoW client's Lua dialect:
# busted (tests) + luacov (coverage) + luacheck (lint) + LuaLS (type check).
FROM debian:bookworm-slim@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc

ARG LUALS_VERSION=3.19.2
RUN apt-get update \
 && apt-get install -y --no-install-recommends lua5.1 liblua5.1-0-dev luarocks build-essential git ca-certificates curl \
 && luarocks --lua-version=5.1 install busted 2.2.0-1 \
 && luarocks --lua-version=5.1 install luacov 0.16.0-1 \
 && luarocks --lua-version=5.1 install luacheck 1.2.0-1 \
 && mkdir -p /opt/luals \
 && curl -fsSL "https://github.com/LuaLS/lua-language-server/releases/download/${LUALS_VERSION}/lua-language-server-${LUALS_VERSION}-linux-x64.tar.gz" \
    | tar -xz -C /opt/luals \
 && ln -s /opt/luals/bin/lua-language-server /usr/local/bin/lua-language-server \
 && apt-get purge -y build-essential && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
WORKDIR /src
