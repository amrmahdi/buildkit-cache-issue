FROM busybox@sha256:3614ca5eacf0a3a1bcc361c939202a974b4902b9334ff36eb29ffe9011aaad83 AS builder
WORKDIR /code
RUN mkdir /src

##########
FROM builder AS final
COPY --from=builder /src/ /src/
WORKDIR /code

