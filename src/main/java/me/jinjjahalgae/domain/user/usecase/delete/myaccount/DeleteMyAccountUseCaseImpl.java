package me.jinjjahalgae.domain.user.usecase.delete.myaccount;

import lombok.RequiredArgsConstructor;
import me.jinjjahalgae.domain.user.UserRepository;
import me.jinjjahalgae.global.exception.ErrorCode;
import me.jinjjahalgae.global.security.jwt.ActiveUserCache;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import me.jinjjahalgae.domain.user.User;

import java.time.Instant;

/**
 * 유저 탈퇴 (soft delete)
 */
@RequiredArgsConstructor
@Service
public class DeleteMyAccountUseCaseImpl implements DeleteMyAccountUseCase {
    private final UserRepository userRepository;
    private final ActiveUserCache activeUserCache;

    @Override
    @Transactional
    public void execute(Long userId) {
        User user = userRepository.findByIdAndDeletedAtIsNull(userId)
                .orElseThrow(() -> ErrorCode.USER_NOT_FOUND.domainException("유저를 찾을 수 없음"));
                
        user.delete(Instant.now());

        // 인증 캐시에서 지운다(커밋 후). 남은 access 토큰은 다음 요청부터 거부된다
        activeUserCache.evictAfterCommit(userId);
    }
} 