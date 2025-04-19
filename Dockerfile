FROM --platform=linux/amd64 openjdk:8-jre-slim

WORKDIR /app

# 复制构建好的 JAR 文件
COPY target/kafka-msk-client-1.0-SNAPSHOT.jar /app/kafka-client.jar

# 设置入口点
ENTRYPOINT ["java", "-jar", "/app/kafka-client.jar"]
