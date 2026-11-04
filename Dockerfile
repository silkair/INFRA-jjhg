# 빌드
FROM gradle:jdk21 as builder

WORKDIR /libs

COPY gradlew .
COPY gradle gradle
COPY build.gradle .
COPY settings.gradle .

RUN ./gradlew dependencies --no-daemon

COPY src src

RUN ./gradlew build --no-daemon -x test

# 실행
# 공식 openjdk 이미지는 지원이 중단돼(Docker Hub 공지) 유지보수되는 Temurin JRE로 바꾼다
FROM eclipse-temurin:21-jre

WORKDIR /app

COPY --from=builder /libs/build/libs/*.jar app.jar

EXPOSE 8080

ENTRYPOINT [ "java", "-Duser.timezone=UTC", "-jar",  "app.jar" ]