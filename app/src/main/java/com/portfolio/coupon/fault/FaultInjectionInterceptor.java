package com.portfolio.coupon.fault;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

/**
 * /coupons/** 요청에만 장애를 주입한다. 헬스체크·버전 엔드포인트에 적용하면
 * ECS 가 태스크를 교체해 버려 "지표 게이트에 의한 롤백" 시연이 흐려진다.
 */
@Component
public class FaultInjectionInterceptor implements HandlerInterceptor {

	private static final Logger log = LoggerFactory.getLogger(FaultInjectionInterceptor.class);

	private final FaultInjector faultInjector;

	public FaultInjectionInterceptor(FaultInjector faultInjector) {
		this.faultInjector = faultInjector;
	}

	@Override
	public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
		if (this.faultInjector.shouldFail()) {
			log.atWarn()
				.addKeyValue("faultInjected", true)
				.addKeyValue("faultRate", this.faultInjector.rate())
				.log("Fault injected: {} {}", request.getMethod(), request.getRequestURI());
			throw new FaultInjectedException();
		}
		return true;
	}

}
