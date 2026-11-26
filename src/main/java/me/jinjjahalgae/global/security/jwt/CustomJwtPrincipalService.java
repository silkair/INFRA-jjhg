package me.jinjjahalgae.global.security.jwt;

import lombok.RequiredArgsConstructor;
import me.jinjjahalgae.global.exception.ErrorCode;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class CustomJwtPrincipalService implements UserDetailsService {
    private final ActiveUserCache activeUserCache;

    @Override
    public CustomJwtPrincipal loadUserByUsername(String userId) {
        Long id = Long.parseLong(userId);

        // 탈퇴하지 않은 회원인지만 확인한다. 회원 엔티티는 조회하지 않는다
        if (!activeUserCache.isActive(id)) {
            throw ErrorCode.USER_NOT_FOUND.serviceException("토큰 sub로 유저를 찾을 수 없음 ID: " + userId);
        }

        return new CustomJwtPrincipal(id);
    }
}
