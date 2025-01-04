FROM alpine
RUN apk add --no-cache gojq
COPY bin/ /opt/mobugen/bin/
COPY jq/ /opt/mobugen/jq/
ENV PATH="$PATH:/opt/mobugen/bin"
WORKDIR /opt/mobugen/data
