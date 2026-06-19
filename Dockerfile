# syntax=docker/dockerfile:1
#
# OpenTripPlanner deploy image for Railway.
#
# Strategy: the transit graph is built at IMAGE-BUILD time and baked in,
# so the running container only has to --load + --serve (fast, cheaper).
# To refresh the GTFS/OSM data, redeploy (Railway "Redeploy" or a push).

ARG MAVEN_VERSION=3.9.9
ARG OSM_URL=https://download.geofabrik.de/africa/ivory-coast-latest.osm.pbf
ARG GTFS_URL=https://gtfs-mobile-api-production.up.railway.app/v1/gtfs/export

########################################
# Stage 1 — build the shaded OTP JAR
########################################
FROM eclipse-temurin:25-jdk AS jarbuild
ARG MAVEN_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
    | tar -xz -C /opt \
 && ln -s "/opt/apache-maven-${MAVEN_VERSION}/bin/mvn" /usr/local/bin/mvn
WORKDIR /src
COPY . .
RUN mvn -q -B -DskipTests -Dmaven.test.skip=true -Dps package
RUN cp otp-shaded/target/otp-shaded-*.jar /otp.jar

########################################
# Stage 2 — download data + build graph
########################################
FROM eclipse-temurin:25-jdk AS graphbuild
ARG OSM_URL
ARG GTFS_URL
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /data
COPY --from=jarbuild /otp.jar /otp.jar
RUN curl -fSL -o /data/data.osm.pbf "${OSM_URL}" \
 && curl -fSL -H 'accept: application/zip' -o /data/GTFS.zip "${GTFS_URL}"
# Build + persist graph.obj. Bump -Xmx if the build OOMs on larger data.
RUN java -Xmx4g -jar /otp.jar --build --save /data

########################################
# Stage 3 — slim runtime
########################################
FROM eclipse-temurin:25-jre AS runtime
WORKDIR /data
COPY --from=jarbuild /otp.jar /otp.jar
COPY --from=graphbuild /data/graph.obj /data/graph.obj
# Respect the container's memory limit instead of a fixed -Xmx.
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:InitialRAMPercentage=50"
EXPOSE 8080
# Railway injects $PORT; default to 8080 for local `docker run`.
CMD ["sh", "-c", "java -jar /otp.jar --load --serve --port ${PORT:-8080} /data"]
