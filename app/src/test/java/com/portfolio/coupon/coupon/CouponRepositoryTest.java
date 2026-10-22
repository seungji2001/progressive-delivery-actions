package com.portfolio.coupon.coupon;

import java.time.Instant;
import java.util.UUID;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class CouponRepositoryTest {

	private final CouponRepository repository = new CouponRepository();

	@Test
	void 저장한_쿠폰을_조회한다() {
		Coupon coupon = new Coupon(UUID.randomUUID(), "u-1", "FIXED", 25000, 3000, 22000, Instant.now(), "v1");
		this.repository.save(coupon);

		assertThat(this.repository.findById(coupon.couponId())).contains(coupon);
	}

	@Test
	void 없는_쿠폰은_빈_값() {
		assertThat(this.repository.findById(UUID.randomUUID())).isEmpty();
	}

}
