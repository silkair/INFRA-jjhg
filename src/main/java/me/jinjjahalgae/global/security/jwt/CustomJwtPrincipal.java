package me.jinjjahalgae.global.security.jwt;

import lombok.RequiredArgsConstructor;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;

import java.util.Collection;
import java.util.Collections;

/**
 * 인증된 사용자. 회원 엔티티 대신 id만 가진다.
 * 필터에서 회원을 DB로 조회하지 않기 위해서다(ActiveUserCache 참고).
 * 회원 엔티티가 필요한 곳은 유스케이스 안에서 id로 가져온다.
 */
@RequiredArgsConstructor
public class CustomJwtPrincipal implements UserDetails {
    private final Long userId;

    @Override
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return Collections.singletonList(new SimpleGrantedAuthority("ROLE_USER"));
    }

    // JWT 방식 사용
    @Override
    public String getPassword() {
        return null;
    }

    // JWT 방식 사용
    @Override
    public String getUsername() {
        return "";
    }

    // getUsername을 사용하지 않고 명시적으로 userId 가져오기 위함
    public Long getUserId() {
        return userId;
    }
}
