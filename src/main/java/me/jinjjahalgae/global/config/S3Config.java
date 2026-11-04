package me.jinjjahalgae.global.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.util.StringUtils;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

import java.net.URI;

@Configuration
public class S3Config {

    // 비워 두면 AWS S3를 그대로 쓴다. MinIO 등 S3 호환 스토리지를 쓸 때만 주소를 넣는다.
    @Value("${cloud.aws.s3.endpoint:}")
    private String endpoint;

    @Bean
    public S3Presigner s3Presigner() {
        S3Presigner.Builder builder = S3Presigner.builder()
                .region(Region.AP_NORTHEAST_2)
                .credentialsProvider(DefaultCredentialsProvider.create());

        if (StringUtils.hasText(endpoint)) {
            builder.endpointOverride(URI.create(endpoint))
                    // MinIO는 버킷을 서브도메인(bucket.host)이 아니라 경로(host/bucket)로 받는다.
                    .serviceConfiguration(S3Configuration.builder()
                            .pathStyleAccessEnabled(true)
                            .build());
        }

        return builder.build();
    }
}
