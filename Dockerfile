FROM alpine
RUN apk add --no-cache gojq
WORKDIR /opt/mobugen
COPY bin/ ./bin/
COPY jq/ ./jq/
ENV PATH="$PATH:/opt/mobugen/bin"
