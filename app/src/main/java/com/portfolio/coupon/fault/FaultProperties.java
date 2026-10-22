package com.portfolio.coupon.fault;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

/**
 * 장애 주입 설정. 범위를 벗어나면 기동 단계에서 실패시킨다 (잘못된 시연 설정 조기 차단).
 *
 * @param rate 0.0~1.0, /coupons/** 에 HTTP 500 을 낼 확률
 * @param delayMs 0~10000, /coupons/** 응답 지연(ms). ALB idle timeout(60s)보다 훨씬 작게 제한해
 * 지연이 연결 끊김(ELB 5xx)이 아니라 TargetResponseTime(p95) 으로 관측되게 한다
 */
@Validated
@ConfigurationProperties("fault")
public record FaultProperties(@DecimalMin("0.0") @DecimalMax("1.0") double rate,
		@Min(0) @Max(10000) long delayMs) {
}
