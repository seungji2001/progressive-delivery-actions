package com.portfolio.coupon.coupon;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.PositiveOrZero;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

@Validated
@ConfigurationProperties("coupon")
public record CouponProperties(@Min(1) @Max(100) long percent, @PositiveOrZero long maxDiscountAmount,
		@PositiveOrZero long minOrderAmount) {
}
