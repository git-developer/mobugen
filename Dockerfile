ARG BASE_IMAGE=ghcr.io/blackzork/mqmgateway
FROM ${BASE_IMAGE}
RUN apk add --no-cache gojq mosquitto-clients
COPY bin/ /opt/mobugen/bin/
COPY jq/ /opt/mobugen/jq/
ENV PATH="$PATH:/opt/mobugen/bin"
WORKDIR /opt/mobugen/data
ENTRYPOINT [ "/usr/bin/env" ]
CMD [ "/bin/sh" ]
