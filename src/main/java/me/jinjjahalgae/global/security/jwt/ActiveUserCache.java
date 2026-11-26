package me.jinjjahalgae.global.security.jwt;

import lombok.extern.slf4j.Slf4j;
import me.jinjjahalgae.domain.user.UserRepository;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.Duration;

/**
 * 탈퇴하지 않은 회원인지 확인한다. 인증된 요청마다 불린다.
 *
 * 전에는 JWT 필터가 요청마다 DB에서 회원을 조회했다. 필터는 OSIV보다 앞에서 돌기 때문에
 * 이 조회가 커넥션을 따로 하나 더 썼다(요청 1건당 커넥션 획득 2회).
 * 이제 Redis에 "유효한 회원" 표시를 두고, 없을 때만 DB를 본다.
 *
 * - 캐시 적중: Redis 조회 1회, DB 커넥션 없음
 * - 캐시 없음: DB 조회 후 Redis에 저장(만료 TTL)
 * - Redis 오류: DB 결과로 판단한다. Redis 장애가 인증 장애로 번지지 않게 한다
 * - 탈퇴: 트랜잭션이 커밋된 뒤 키를 지운다. 지우기에 실패해도 TTL이 지나면 사라진다
 */
@Slf4j
@Component
public class ActiveUserCache {

    private static final String KEY_PREFIX = "auth:active-user:";
    private static final Duration TTL = Duration.ofMinutes(10);
    private static final String ACTIVE = "1";

    private final StringRedisTemplate redis;
    private final UserRepository userRepository;

    public ActiveUserCache(RedisConnectionFactory connectionFactory, UserRepository userRepository) {
        this.redis = new StringRedisTemplate(connectionFactory);
        this.userRepository = userRepository;
    }

    public boolean isActive(Long userId) {
        String key = KEY_PREFIX + userId;

        try {
            if (ACTIVE.equals(redis.opsForValue().get(key))) {
                return true;
            }
        } catch (RuntimeException e) {
            log.warn("Redis 조회 실패, DB로 확인: userId={}, {}", userId, e.getMessage());
            return userRepository.existsByIdAndDeletedAtIsNull(userId);
        }

        boolean active = userRepository.existsByIdAndDeletedAtIsNull(userId);
        if (active) {
            try {
                redis.opsForValue().set(key, ACTIVE, TTL);
            } catch (RuntimeException e) {
                log.warn("Redis 저장 실패: userId={}, {}", userId, e.getMessage());
            }
        }
        return active;
    }

    /**
     * 탈퇴 처리 트랜잭션 안에서 부른다. 키는 커밋된 뒤에 지운다.
     * 커밋 전에 지우면, 그사이 다른 요청이 아직 탈퇴 전인 DB를 보고 키를 다시 만들 수 있다.
     */
    public void evictAfterCommit(Long userId) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    evict(userId);
                }
            });
        } else {
            evict(userId);
        }
    }

    private void evict(Long userId) {
        try {
            redis.delete(KEY_PREFIX + userId);
        } catch (RuntimeException e) {
            log.error("Redis 키 삭제 실패, TTL({}) 뒤 만료: userId={}, {}", TTL, userId, e.getMessage());
        }
    }
}
