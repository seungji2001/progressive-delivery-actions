package com.portfolio.coupon.coupon;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class GradeBonusTest {

	@Test
	void 등급은_0에서_3_사이() {
		assertThat(CouponService.gradeOf("u-1")).isEqualTo(1);
		assertThat(CouponService.gradeOf("smoke")).isEqualTo(3);
	}

}
