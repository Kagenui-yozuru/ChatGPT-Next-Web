FROM node:18-alpine AS base

FROM base AS deps

ARG ALPINE_MIRROR="https://mirrors.aliyun.com/alpine/v3.18/main"
RUN echo "${ALPINE_MIRROR}" > /etc/apk/repositories
RUN apk add --no-cache libc6-compat

WORKDIR /mydata/chatGPT

COPY package.json yarn.lock ./

RUN yarn config set registry 'https://registry.npmmirror.com/'
RUN yarn install

FROM base AS builder

ARG ALPINE_MIRROR="https://mirrors.aliyun.com/alpine/v3.18/main"
RUN echo "${ALPINE_MIRROR}" > /etc/apk/repositories
RUN apk update && apk add --no-cache git

ENV OPENAI_API_KEY=""
ENV CODE=""

WORKDIR /mydata/chatGPT
COPY --from=deps /mydata/chatGPT/node_modules ./node_modules
COPY . .

RUN yarn build

FROM base AS runner
ARG ALPINE_MIRROR="https://mirrors.aliyun.com/alpine/v3.18/main"
RUN echo "${ALPINE_MIRROR}" > /etc/apk/repositories
WORKDIR /mydata/chatGPT

RUN apk add proxychains-ng

ENV PROXY_URL=""
ENV OPENAI_API_KEY=""
ENV CODE=""

COPY --from=builder /mydata/chatGPT/public ./public
COPY --from=builder /mydata/chatGPT/.next/standalone ./
COPY --from=builder /mydata/chatGPT/.next/static ./.next/static
COPY --from=builder /mydata/chatGPT/.next/server ./.next/server

EXPOSE 3000

CMD if [ -n "$PROXY_URL" ]; then \
        export HOSTNAME="127.0.0.1"; \
        protocol=$(echo $PROXY_URL | cut -d: -f1); \
        host=$(echo $PROXY_URL | cut -d/ -f3 | cut -d: -f1); \
        port=$(echo $PROXY_URL | cut -d: -f3); \
        conf=/etc/proxychains.conf; \
        echo "strict_chain" > $conf; \
        echo "proxy_dns" >> $conf; \
        echo "remote_dns_subnet 224" >> $conf; \
        echo "tcp_read_time_out 15000" >> $conf; \
        echo "tcp_connect_time_out 8000" >> $conf; \
        echo "localnet 127.0.0.0/255.0.0.0" >> $conf; \
        echo "localnet ::1/128" >> $conf; \
        echo "[ProxyList]" >> $conf; \
        echo "$protocol $host $port" >> $conf; \
        cat /etc/proxychains.conf; \
        proxychains -f $conf node server.js; \
    else \
        node server.js; \
    fi
