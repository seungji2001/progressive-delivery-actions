package com.portfolio.coupon.coupon;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class PercentageDiscountPolicyTest {

	private final PercentageDiscountPolicy policy = new PercentageDiscountPolicy(new CouponProperties(10, 5000, 10000));

	@Test
	void 최소_주문금액_미만이면_예외() {
		assertThatThrownBy(() -> this.policy.discount(9999)).isInstanceOf(MinOrderAmountNotMetException.class);
	}

	@Test
	void 최소_주문금액과_같으면_할인() {
		assertThat(this.policy.discount(10000)).isEqualTo(1000);
	}

	@Test
	void 원_단위_절사() {
		assertThat(this.policy.discount(12345)).isEqualTo(1234);
	}

	@Test
	void 최대_할인_금액_상한() {
		assertThat(this.policy.discount(80000)).isEqualTo(5000);
	}

	@Test
	void 할인_타입은_PERCENTAGE() {
		assertThat(this.policy.type()).isEqualTo("PERCENTAGE");
	}

}
