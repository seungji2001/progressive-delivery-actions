package com.portfolio.coupon.web;

import java.io.IOException;

import com.portfolio.coupon.version.VersionInfo;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * 에러·장애 주입 응답을 포함한 모든 응답에 버전 헤더를 단다.
 * 체인 실행 전에 설정해야 응답이 커밋된 뒤에도 헤더가 유지된다.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class AppVersionHeaderFilter extends OncePerRequestFilter {

	public static final String HEADER = "X-App-Version";

	private final VersionInfo versionInfo;

	public AppVersionHeaderFilter(VersionInfo versionInfo) {
		this.versionInfo = versionInfo;
	}

	@Override
	protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
			throws ServletException, IOException {
		response.setHeader(HEADER, this.versionInfo.version());
		chain.doFilter(request, response);
	}

}
