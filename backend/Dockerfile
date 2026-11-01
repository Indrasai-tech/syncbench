FROM swift:5.10-jammy AS build
WORKDIR /build
COPY backend/Package.swift ./Package.swift
COPY backend/Sources ./Sources
RUN swift build -c release --product syncbench-server

FROM swift:5.10-jammy
WORKDIR /app
COPY --from=build /build/.build/release/syncbench-server /usr/local/bin/syncbench-server
COPY scenarios ./scenarios
ENV SCENARIOS_DIR=/app/scenarios DATA_DIR=/app/data
EXPOSE 8000
CMD ["syncbench-server"]
