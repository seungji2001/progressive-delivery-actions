package com.portfolio.coupon.coupon;

import java.util.UUID;

public class CouponNotFoundException extends RuntimeException {

	public CouponNotFoundException(UUID couponId) {
		super("쿠폰을 찾을 수 없습니다: " + couponId);
	}

}
