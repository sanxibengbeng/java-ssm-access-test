import com.amazonaws.auth.AWSCredentialsProvider;
import com.amazonaws.auth.DefaultAWSCredentialsProviderChain;
import com.amazonaws.services.secretsmanager.AWSSecretsManager;
import com.amazonaws.services.secretsmanager.AWSSecretsManagerClientBuilder;
import com.amazonaws.services.secretsmanager.model.GetSecretValueRequest;
import com.amazonaws.services.secretsmanager.model.GetSecretValueResult;
import org.apache.kafka.clients.consumer.KafkaConsumer;

import java.util.Properties;

public class KafkaClient {
    public static void main(String[] args) {
        try {
            System.out.println("Starting Kafka MSK client...");
            
            // 获取环境变量
            String region = System.getenv("AWS_REGION");
            String secretName = System.getenv("SECRET_NAME");
            String bootstrapServers = System.getenv("BOOTSTRAP_SERVERS");
            String groupId = System.getenv("GROUP_ID");
            
            System.out.println("Using region: " + region);
            System.out.println("Using secret: " + secretName);
            System.out.println("Using bootstrap servers: " + bootstrapServers);
            System.out.println("Using group ID: " + groupId);
            
            // 获取 AWS Secrets Manager 客户端
            System.out.println("Initializing AWS Secrets Manager client...");
            AWSSecretsManager secretsManager = AWSSecretsManagerClientBuilder.standard()
                .withCredentials(DefaultAWSCredentialsProviderChain.getInstance())
                .withRegion(region)
                .build();

            // 获取 Secret 值
            System.out.println("Retrieving secret: " + secretName);
            GetSecretValueRequest getSecretValueRequest = new GetSecretValueRequest().withSecretId(secretName);
            GetSecretValueResult secretValueResult = secretsManager.getSecretValue(getSecretValueRequest);

            // 解析 Secret 内容
            String secretString = secretValueResult.getSecretString();
            System.out.println("Secret retrieved successfully");
            
            String username = parseJson(secretString, "username");
            String password = parseJson(secretString, "password");
            System.out.println("Credentials parsed successfully");

            // 配置 Kafka 客户端
            Properties props = new Properties();
            props.put("bootstrap.servers", bootstrapServers);
            props.put("group.id", groupId);
            props.put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
            props.put("value.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");

            // 配置 SASL/SCRAM 认证
            props.put("security.protocol", "SASL_SSL");
            props.put("sasl.mechanism", "SCRAM-SHA-512");
            props.put("sasl.jaas.config", String.format(
                "org.apache.kafka.common.security.scram.ScramLoginModule required username=\"%s\" password=\"%s\";",
                username, password));

            System.out.println("Kafka properties configured");
            System.out.println("Creating Kafka consumer...");
            
            // 创建 Kafka 消费者
            KafkaConsumer<String, String> consumer = new KafkaConsumer<>(props);
            System.out.println("Kafka consumer created successfully");
            
            // 使用 consumer 进行消费操作
            consumer.close();
            System.out.println("Test completed successfully");
            
            // 保持应用运行
            while(true) {
                System.out.println("Application running...");
                Thread.sleep(60000);
            }
        } catch (Exception e) {
            System.err.println("Error occurred: " + e.getMessage());
            e.printStackTrace();
        }
    }

    // 使用Jackson解析JSON
    private static String parseJson(String json, String key) {
        try {
            com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
            com.fasterxml.jackson.databind.JsonNode rootNode = mapper.readTree(json);
            return rootNode.path(key).asText();
        } catch (Exception e) {
            e.printStackTrace();
            return "";
        }
    }
}
