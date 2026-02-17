FROM rust:1.75 as builder

WORKDIR /app
COPY . .
RUN cargo build --release -p broadcaster

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/broadcaster /usr/local/bin/broadcaster

CMD ["broadcaster"]
