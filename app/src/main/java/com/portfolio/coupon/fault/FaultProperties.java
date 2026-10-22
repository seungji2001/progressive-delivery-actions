package com.portfolio.coupon.fault;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

/**
 * 장애 주입 설정. 범위를 벗어나면 기동 단계에서 실패시킨다 (잘못된 시연 설정 조기 차단).
 */
@Validated
@ConfigurationProperties("fault")
public record FaultProperties(@DecimalMin("0.0") @DecimalMax("1.0") double rate) {
}
