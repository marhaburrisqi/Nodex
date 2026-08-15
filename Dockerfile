FROM alpine:3.20

RUN apk add --no-cache curl ca-certificates tzdata

WORKDIR /app

COPY ddns.sh /usr/local/bin/nodex
RUN chmod +x /usr/local/bin/nodex

USER guest

ENTRYPOINT ["/usr/local/bin/nodex"]
CMD ["--daemon"]