package com.portfolio.coupon.coupon;

import jakarta.validation.constraints.PositiveOrZero;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

@Validated
@ConfigurationProperties("coupon")
public record CouponProperties(@PositiveOrZero long fixedAmount, @PositiveOrZero long minOrderAmount) {
}
