package me.jinjjahalgae.global.config;

import net.javacrumbs.shedlock.core.LockProvider;
import net.javacrumbs.shedlock.provider.redis.spring.RedisLockProvider;
import net.javacrumbs.shedlock.spring.annotation.EnableSchedulerLock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.connection.RedisConnectionFactory;

/**
 * 스케줄 작업 분산 락 설정 (ShedLock)
 *
 * 앱 파드가 여러 개면 @Scheduled 작업이 파드마다 실행된다.
 * 락을 Redis에 두고, 락을 먼저 잡은 파드 하나만 작업을 실행하게 한다.
 * 락 키: job-lock:jjhg:{작업 이름}
 */
@Configuration
@EnableSchedulerLock(defaultLockAtMostFor = "PT10M")
public class SchedulerLockConfig {

    @Bean
    public LockProvider lockProvider(RedisConnectionFactory connectionFactory) {
        return new RedisLockProvider(connectionFactory, "jjhg");
    }
}
