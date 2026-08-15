FROM alpine:3.20

RUN apk add --no-cache curl bash tzdata

WORKDIR /app
COPY ddns.sh /app/ddns.sh
RUN chmod +x /app/ddns.sh

ENTRYPOINT ["/app/ddns.sh"]
CMD ["--daemon"]
