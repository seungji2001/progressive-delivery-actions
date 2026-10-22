# syntax=docker/dockerfile:1

# ---- build ----
FROM eclipse-temurin:21-jdk AS build
WORKDIR /workspace
COPY gradlew settings.gradle.kts build.gradle.kts ./
COPY gradle gradle
RUN ./gradlew --no-daemon dependencies > /dev/null
COPY src src
RUN ./gradlew --no-daemon bootJar -x test \
	&& java -Djarmode=tools -jar build/libs/coupon-api-*.jar extract --layers --launcher --destination extracted

# ---- runtime ----
FROM eclipse-temurin:21-jre
ARG APP_VERSION=unknown
ARG GIT_SHA=unknown
ENV APP_VERSION=${APP_VERSION} \
	GIT_SHA=${GIT_SHA} \
	JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"

RUN groupadd --system app && useradd --system --gid app --no-create-home app
WORKDIR /app
# 변경 빈도가 낮은 레이어부터 복사해 캐시 효율을 높인다
COPY --from=build /workspace/extracted/dependencies/ ./
COPY --from=build /workspace/extracted/spring-boot-loader/ ./
COPY --from=build /workspace/extracted/snapshot-dependencies/ ./
COPY --from=build /workspace/extracted/application/ ./

USER app
EXPOSE 8080
# HEALTHCHECK 는 두지 않는다: ALB 대상 그룹 헬스체크(/health/readiness)를 사용
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
