package com.portfolio.coupon.coupon;

import java.time.Instant;
import java.util.UUID;

public record Coupon(UUID couponId, String userId, String discountType, long orderAmount, long discountAmount,
		long finalAmount, Instant issuedAt, String appVersion) {
}
